//
//  FeatherDatabaseSQLiteTestSuite.swift
//  feather-database-sqlite
//
//  Created by Tibor Bödecs on 2026. 01. 10..
//
//
import FeatherDatabase
import Logging
import SQLiteNIO
import Testing

@testable import FeatherDatabaseSQLite
@testable import SQLiteNIOExtras

#if ServiceLifecycle
import ServiceLifecycleTestKit
#endif

@Suite
struct FeatherDatabaseSQLiteTestSuite {

    func runUsingTestDatabaseClient(
        _ closure: ((DatabaseClientSQLite) async throws -> Void)
    ) async throws {
        try await withLogger(Logger(label: "sqlite-test")) { _ in
            let configuration = SQLiteClient.Configuration(
                storage: .memory,
            )

            let client = SQLiteClient(configuration: configuration)

            let database = DatabaseClientSQLite(
                client: client
            )

            try await client.run()
            do {
                try await closure(database)
                await client.shutdown()
            }
            catch {
                await client.shutdown()
                throw error
            }
        }
    }

    @Test
    func foreignKeySupport() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: "PRAGMA foreign_keys"
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "foreign_keys", as: Int.self)
                        == 1
                )
            }
        }
    }

    @Test
    func tableCreation() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS "galaxies" (
                            "id" INTEGER PRIMARY KEY,
                            "name" TEXT
                        );
                        """#
                )

                let results = try await connection.run(
                    query: #"""
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'table'
                        ORDER BY name;
                        """#
                ) { try await $0.collect() }

                #expect(results.count == 1)

                let item = results[0]
                let name = try item.decode(column: "name", as: String.self)
                #expect(name == "galaxies")
            }
        }
    }

    @Test
    func tableInsert() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS "galaxies" (
                            "id" INTEGER PRIMARY KEY,
                            "name" TEXT
                        );
                        """#
                )

                let name1 = "Andromeda"
                let name2 = "Milky Way"
                let id1: Int? = nil
                let id2: Int? = nil

                try await connection.run(
                    query: #"""
                        INSERT INTO "galaxies"
                            ("id", "name")
                        VALUES
                            (\#(id1), \#(name1)),
                            (\#(id2), \#(name2));
                        """#
                )

                let results = try await connection.run(
                    query: #"""
                        SELECT * FROM "galaxies" ORDER BY "name" ASC;
                        """#
                ) { try await $0.collect() }

                #expect(results.count == 2)

                let item1 = results[0]
                let name1result = try item1.decode(
                    column: "name",
                    as: String.self
                )
                #expect(name1result == name1)

                let item2 = results[1]
                let name2result = try item2.decode(
                    column: "name",
                    as: String.self
                )
                #expect(name2result == name2)
            }
        }
    }

    @Test
    func rowDecoding() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "foo" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "foo"
                            ("id", "value")
                        VALUES
                            (1, 'abc'),
                            (2, NULL);
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "id", "value"
                            FROM "foo"
                            ORDER BY "id";
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 2)

                let item1 = result[0]
                let item2 = result[1]

                #expect(try item1.decode(column: "id", as: Int.self) == 1)
                #expect(try item2.decode(column: "id", as: Int.self) == 2)

                #expect(
                    try item1.decode(column: "id", as: Int?.self) == .some(1)
                )
                #expect(
                    (try? item1.decode(column: "value", as: Int?.self)) == nil
                )

                #expect(
                    try item1.decode(column: "value", as: String.self) == "abc"
                )
                #expect(
                    (try? item2.decode(column: "value", as: String.self)) == nil
                )

                #expect(
                    (try item1.decode(column: "value", as: String?.self))
                        == .some("abc")
                )
                #expect(
                    (try item2.decode(column: "value", as: String?.self))
                        == .none
                )
            }
        }
    }

    @Test
    func queryEncoding() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let tableName = "foo"
                let idColumn = "id"
                let valueColumn = "value"
                let row1: (Int, String?) = (1, "abc")
                let row2: (Int, String?) = (2, nil)

                try await connection.run(
                    query: #"""
                        CREATE TABLE \#(unescaped: tableName) (
                            \#(unescaped: idColumn) INTEGER NOT NULL PRIMARY KEY,
                            \#(unescaped: valueColumn) TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO \#(unescaped: tableName)
                            (\#(unescaped: idColumn), \#(unescaped: valueColumn))
                        VALUES
                            (\#(row1.0), \#(row1.1)),
                            (\#(row2.0), \#(row2.1));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT \#(unescaped: idColumn), \#(unescaped: valueColumn)
                            FROM \#(unescaped: tableName)
                            ORDER BY \#(unescaped: idColumn) ASC;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 2)

                let item1 = result[0]
                let item2 = result[1]

                #expect(try item1.decode(column: "id", as: Int.self) == 1)
                #expect(try item2.decode(column: "id", as: Int.self) == 2)

                #expect(
                    try item1.decode(column: "value", as: String?.self) == "abc"
                )
                #expect(
                    try item2.decode(column: "value", as: String?.self) == nil
                )
            }
        }
    }

    @Test
    func boundOptionalInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let boundString: String? = "alpha"
                let missingString: String? = nil
                let boundInt: Int? = 21
                let missingInt: Int? = nil
                let boundFloat: Float? = 1.25
                let missingFloat: Float? = nil
                let boundDouble: Double? = 3.75
                let missingDouble: Double? = nil
                let boundBool: Bool? = true
                let missingBool: Bool? = nil

                struct OptionalRow: Sendable {
                    let boundString: String?
                    let missingString: String?
                    let boundInt: Int?
                    let missingInt: Int?
                    let boundFloat: Double?
                    let missingFloat: Double?
                    let boundDouble: Double?
                    let missingDouble: Double?
                    let boundBool: Bool?
                    let missingBool: Bool?

                    init(_ row: DatabaseRow) throws {
                        self.boundString = try row.decode(
                            column: "bound_string",
                            as: String?.self
                        )
                        self.missingString = try row.decode(
                            column: "missing_string",
                            as: String?.self
                        )
                        self.boundInt = try row.decode(
                            column: "bound_int",
                            as: Int?.self
                        )
                        self.missingInt = try row.decode(
                            column: "missing_int",
                            as: Int?.self
                        )
                        self.boundFloat = try row.decode(
                            column: "bound_float",
                            as: Double?.self
                        )
                        self.missingFloat = try row.decode(
                            column: "missing_float",
                            as: Double?.self
                        )
                        self.boundDouble = try row.decode(
                            column: "bound_double",
                            as: Double?.self
                        )
                        self.missingDouble = try row.decode(
                            column: "missing_double",
                            as: Double?.self
                        )
                        self.boundBool = try row.decode(
                            column: "bound_bool",
                            as: Bool?.self
                        )
                        self.missingBool = try row.decode(
                            column: "missing_bool",
                            as: Bool?.self
                        )
                    }
                }

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            \#(boundString) AS "bound_string",
                            \#(missingString) AS "missing_string",
                            \#(boundInt) AS "bound_int",
                            \#(missingInt) AS "missing_int",
                            \#(boundFloat) AS "bound_float",
                            \#(missingFloat) AS "missing_float",
                            \#(boundDouble) AS "bound_double",
                            \#(missingDouble) AS "missing_double",
                            \#(boundBool) AS "bound_bool",
                            \#(missingBool) AS "missing_bool";
                        """#
                ) { try await $0.collect().map { try OptionalRow($0) } }

                #expect(result.count == 1)
                #expect(result[0].boundString == "alpha")
                #expect(result[0].missingString == nil)
                #expect(result[0].boundInt == 21)
                #expect(result[0].missingInt == nil)
                #expect(result[0].boundFloat == 1.25)
                #expect(result[0].missingFloat == nil)
                #expect(result[0].boundDouble == 3.75)
                #expect(result[0].missingDouble == nil)
                #expect(result[0].boundBool == true)
                #expect(result[0].missingBool == nil)
            }
        }
    }

    @Test
    func unescapedOptionalInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "fragments" (
                            "alpha" TEXT NOT NULL
                        );
                        """#
                )
                try await connection.run(
                    query: #"""
                        INSERT INTO "fragments"
                            ("alpha")
                        VALUES
                            ('omega');
                        """#
                )

                let rawColumn: String? = "alpha"
                let missingColumn: String? = nil
                let rawInt: Int? = 7
                let missingInt: Int? = nil
                let rawFloat: Float? = 2.5
                let missingFloat: Float? = nil
                let rawDouble: Double? = 4.5
                let missingDouble: Double? = nil
                let rawBool: Bool? = true
                let missingBool: Bool? = nil

                struct RawOptionalRow: Sendable {
                    let rawColumn: String?
                    let missingColumn: String?
                    let rawInt: Int?
                    let missingInt: Int?
                    let rawFloat: Double?
                    let missingFloat: Double?
                    let rawDouble: Double?
                    let missingDouble: Double?
                    let rawBool: Bool?
                    let missingBool: Bool?

                    init(_ row: DatabaseRow) throws {
                        self.rawColumn = try row.decode(
                            column: "raw_column",
                            as: String?.self
                        )
                        self.missingColumn = try row.decode(
                            column: "missing_column",
                            as: String?.self
                        )
                        self.rawInt = try row.decode(
                            column: "raw_int",
                            as: Int?.self
                        )
                        self.missingInt = try row.decode(
                            column: "missing_int",
                            as: Int?.self
                        )
                        self.rawFloat = try row.decode(
                            column: "raw_float",
                            as: Double?.self
                        )
                        self.missingFloat = try row.decode(
                            column: "missing_float",
                            as: Double?.self
                        )
                        self.rawDouble = try row.decode(
                            column: "raw_double",
                            as: Double?.self
                        )
                        self.missingDouble = try row.decode(
                            column: "missing_double",
                            as: Double?.self
                        )
                        self.rawBool = try row.decode(
                            column: "raw_bool",
                            as: Bool?.self
                        )
                        self.missingBool = try row.decode(
                            column: "missing_bool",
                            as: Bool?.self
                        )
                    }
                }

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            \#(unescaped: rawColumn) AS "raw_column",
                            \#(unescaped: missingColumn) AS "missing_column",
                            \#(unescaped: rawInt) AS "raw_int",
                            \#(unescaped: missingInt) AS "missing_int",
                            \#(unescaped: rawFloat) AS "raw_float",
                            \#(unescaped: missingFloat) AS "missing_float",
                            \#(unescaped: rawDouble) AS "raw_double",
                            \#(unescaped: missingDouble) AS "missing_double",
                            \#(unescaped: rawBool) AS "raw_bool",
                            \#(unescaped: missingBool) AS "missing_bool"
                        FROM "fragments";
                        """#
                ) { try await $0.collect().map { try RawOptionalRow($0) } }

                #expect(result.count == 1)
                #expect(result[0].rawColumn == "omega")
                #expect(result[0].missingColumn == nil)
                #expect(result[0].rawInt == 7)
                #expect(result[0].missingInt == nil)
                #expect(result[0].rawFloat == 2.5)
                #expect(result[0].missingFloat == nil)
                #expect(result[0].rawDouble == 4.5)
                #expect(result[0].missingDouble == nil)
                #expect(result[0].rawBool == true)
                #expect(result[0].missingBool == nil)
            }
        }
    }

    @Test
    func arrayInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "array_samples" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "name" TEXT NOT NULL,
                            "ratio" REAL NOT NULL,
                            "score" REAL NOT NULL,
                            "active" INTEGER NOT NULL
                        );
                        """#
                )
                try await connection.run(
                    query: #"""
                        INSERT INTO "array_samples"
                            ("id", "name", "ratio", "score", "active")
                        VALUES
                            (1, 'alpha', 1.5, 3.5, 1),
                            (2, 'beta', 2.25, 4.75, 0);
                        """#
                )

                let names = ["alpha", "omega"]
                let ids = [1, 99]
                let ratios: [Float] = [1.5, 9.5]
                let scores = [3.5, 9.75]
                let flags = [true, false]

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            "id",
                            "name"
                        FROM "array_samples"
                        WHERE
                            "name" IN (\#(names))
                            AND "id" IN (\#(ids))
                            AND "ratio" IN (\#(ratios))
                            AND "score" IN (\#(scores))
                            AND "active" IN (\#(flags))
                        ORDER BY "id";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(try result[0].decode(column: "id", as: Int.self) == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func optionalArrayInterpolationRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "optional_array_samples" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "name" TEXT NOT NULL,
                            "ratio" REAL NOT NULL,
                            "score" REAL NOT NULL,
                            "active" INTEGER NOT NULL
                        );
                        """#
                )
                try await connection.run(
                    query: #"""
                        INSERT INTO "optional_array_samples"
                            ("id", "name", "ratio", "score", "active")
                        VALUES
                            (1, 'alpha', 1.5, 3.5, 1),
                            (2, 'beta', 2.25, 4.75, 0);
                        """#
                )

                let names: [String?] = ["alpha", nil, "omega"]
                let ids: [Int?] = [1, nil, 99]
                let ratios: [Float?] = [1.5, nil, 9.5]
                let scores: [Double?] = [3.5, nil, 9.75]
                let flags: [Bool?] = [true, nil, false]

                let result = try await connection.run(
                    query: #"""
                        SELECT
                            "id",
                            "name"
                        FROM "optional_array_samples"
                        WHERE
                            "name" IN (\#(names))
                            AND "id" IN (\#(ids))
                            AND "ratio" IN (\#(ratios))
                            AND "score" IN (\#(scores))
                            AND "active" IN (\#(flags))
                        ORDER BY "id";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(try result[0].decode(column: "id", as: Int.self) == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func unsafeSQLBindings() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "widgets" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "name" TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "widgets"
                            ("id", "name")
                        VALUES
                            (\#(1), \#("gizmo"));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "name"
                            FROM "widgets"
                            WHERE "id" = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "gizmo"
                )
            }
        }
    }

    @Test
    func optionalStringInterpolationNil() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "notes" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "body" TEXT
                        );
                        """#
                )

                let body: String? = nil

                try await connection.run(
                    query: #"""
                        INSERT INTO "notes"
                            ("id", "body")
                        VALUES
                            (1, \#(body));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "body"
                            FROM "notes"
                            WHERE "id" = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "body", as: String?.self)
                        == nil
                )
            }
        }
    }

    @Test
    func sqliteDataInterpolation() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "tags" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "label" TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "tags"
                            ("id", "label")
                        VALUES
                            (1, \#("alpha"));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "label"
                            FROM "tags"
                            WHERE "id" = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "label", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func booleanInterpolation() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT
                            \#(true) AS "enabled",
                            \#(false) AS "disabled";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "enabled", as: Int.self) == 1
                )
                #expect(
                    try result[0].decode(column: "disabled", as: Int.self) == 0
                )
            }
        }
    }

    @Test
    func booleanInterpolationInWhereClause() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "flags" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "is_enabled" INTEGER NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "flags"
                            ("id", "is_enabled")
                        VALUES
                            (1, 1),
                            (2, 0);
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT COUNT(*) AS "count"
                        FROM "flags"
                        WHERE "is_enabled" = \#(true);
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "count", as: Int.self) == 1
                )
            }
        }
    }

    @Test
    func resultSequenceIterator() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "numbers" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "numbers"
                            ("id", "value")
                        VALUES
                            (1, 'one'),
                            (2, 'two');
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT "id", "value"
                        FROM "numbers"
                        ORDER BY "id";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 2)
                let first = result[0]
                let second = result[1]

                #expect(try first.decode(column: "id", as: Int.self) == 1)
                #expect(
                    try first.decode(column: "value", as: String.self) == "one"
                )

                #expect(try second.decode(column: "id", as: Int.self) == 2)
                #expect(
                    try second.decode(column: "value", as: String.self) == "two"
                )
            }
        }
    }

    @Test
    func collectFirstReturnsFirstRow() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "widgets" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "name" TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "widgets"
                            ("id", "name")
                        VALUES
                            (1, 'alpha'),
                            (2, 'beta');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "name"
                            FROM "widgets"
                            ORDER BY "id" ASC;
                            """#
                    ) { try await $0.collect() }
                    .first

                #expect(result != nil)
                #expect(
                    try result?.decode(column: "name", as: String.self)
                        == "alpha"
                )
            }
        }
    }

    @Test
    func transactionSuccess() async throws {
        try await runUsingTestDatabaseClient { database in

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "items" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "name" TEXT NOT NULL
                        );
                        """#
                )
            }

            try await database.withTransaction { connection in
                try await connection.run(
                    query: #"""
                        INSERT INTO "items"
                            ("id", "name")
                        VALUES
                            (1, 'widget');
                        """#
                )
            }

            try await database.withConnection { connection in

                let result = try await connection.run(
                    query: #"""
                        SELECT "name"
                        FROM "items"
                        WHERE "id" = 1;
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "name", as: String.self)
                        == "widget"
                )
            }
        }
    }

    @Test
    func transactionFailurePropagates() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "dummy" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "name" TEXT NOT NULL
                        );
                        """#
                )
            }

            do {
                try await database.withTransaction { connection in
                    try await connection.run(
                        query: #"""
                            INSERT INTO "dummy"
                                ("id", "name")
                            VALUES
                                (1, 'ok');
                            """#
                    )

                    try await connection.run(
                        query: #"""
                            INSERT INTO "dummy"
                                ("id", "name")
                            VALUES
                                (2, NULL);
                            """#
                    )
                }
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }
            catch DatabaseError.transaction(let error) {
                #expect(error.beginError == nil)
                #expect(error.closureError != nil)
                #expect(
                    error.closureError.debugDescription.contains(
                        "NOT NULL constraint failed"
                    )
                )
                #expect(error.rollbackError == nil)
                #expect(error.commitError == nil)
            }
            catch {
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }

            try await database.withConnection { connection in
                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "id"
                            FROM "dummy";
                            """#
                    ) { try await $0.collect() }

                #expect(result.isEmpty)
            }
        }
    }

    @Test
    func transactionClosureErrorPropagates() async throws {
        try await runUsingTestDatabaseClient { database in
            enum TestError: Error, Equatable {
                case boom
            }

            do {
                _ = try await database.withTransaction { _ in
                    throw TestError.boom
                }
                Issue.record("Expected transaction error to be thrown.")
            }
            catch DatabaseError.transaction(let error) {
                #expect(error.beginError == nil)
                #expect(error.commitError == nil)
                #expect(error.rollbackError == nil)
                #expect((error.closureError as? TestError) == .boom)
                #expect(error.file.isEmpty == false)
                #expect(error.line > 0)
            }
            catch {
                Issue.record(
                    "Expected database transaction error to be thrown."
                )
            }
        }
    }

    @Test
    func doubleRoundTrip() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "measurements" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" REAL NOT NULL
                        );
                        """#
                )

                let expected = 1.5

                try await connection.run(
                    query: #"""
                        INSERT INTO "measurements"
                            ("id", "value")
                        VALUES
                            (1, \#(expected));
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "value"
                            FROM "measurements"
                            WHERE "id" = 1;
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)
                #expect(
                    try result[0].decode(column: "value", as: Double.self)
                        == expected
                )
            }
        }
    }

    @Test
    func missingColumnThrows() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "items" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "items"
                            ("id", "value")
                        VALUES
                            (1, 'abc');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "id"
                            FROM "items";
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: String.self)
                    Issue.record("Expected decoding a missing column to throw.")
                }
                catch DecodingError.dataCorrupted {

                }
                catch {
                    Issue.record(
                        "Expected a dataCorrupted error for missing column."
                    )
                }
            }
        }
    }

    @Test
    func typeMismatchThrows() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "items" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "items"
                            ("id", "value")
                        VALUES
                            (1, 'abc');
                        """#
                )

                let result =
                    try await connection.run(
                        query: #"""
                            SELECT "value"
                            FROM "items";
                            """#
                    ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: Int.self)
                    Issue.record("Expected decoding a string as Int to throw.")
                }
                catch DecodingError.typeMismatch {

                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error when decoding a string as Int."
                    )
                }
            }
        }
    }

    @Test
    func nullDecodingThrowsTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "nullable_values" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" INTEGER
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "nullable_values"
                            ("id", "value")
                        VALUES
                            (1, NULL);
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT "value"
                        FROM "nullable_values";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0].decode(column: "value", as: Int.self)
                    Issue.record("Expected decoding NULL as Int to throw.")
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains("Could not convert")
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error when decoding NULL as Int."
                    )
                }
            }
        }
    }

    @Test
    func nonSQLiteDecodableTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            struct CustomValue: Decodable, Sendable {
                let value: String
            }

            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE "custom_types" (
                            "id" INTEGER NOT NULL PRIMARY KEY,
                            "value" TEXT NOT NULL
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "custom_types"
                            ("id", "value")
                        VALUES
                            (1, 'alpha');
                        """#
                )

                let result = try await connection.run(
                    query: #"""
                        SELECT "value"
                        FROM "custom_types";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: CustomValue.self
                        )
                    Issue.record(
                        "Expected decoding non-SQLiteDecodable type to throw."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Keyed decoding is not supported."
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error for non-SQLiteDecodable types."
                    )
                }
            }
        }
    }

    @Test
    func singleValueDecodingTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            struct CustomValue: Decodable, Sendable {
                let value: String
            }

            struct Wrapper: Decodable, Sendable {
                let value: CustomValue

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    value = try container.decode(CustomValue.self)
                }
            }

            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT 'abc' AS "value";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: Wrapper.self
                        )
                    Issue.record(
                        "Expected single-value decoding to throw typeMismatch."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Data is not convertible"
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error for single-value decoding."
                    )
                }
            }
        }
    }

    @Test
    func nonDecodingErrorThrownFromDecodeIsMapped() async throws {
        try await runUsingTestDatabaseClient { database in
            enum TestError: Error {
                case boom
            }

            struct ThrowingValue: Decodable, Sendable {
                init(from _: Decoder) throws {
                    throw TestError.boom
                }
            }

            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT 'abc' AS "value";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: ThrowingValue.self
                        )
                    Issue.record(
                        "Expected non-DecodingError to map to typeMismatch."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Data is not convertible"
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected typeMismatch when decoding throws non-DecodingError."
                    )
                }
            }
        }
    }

    @Test
    func unkeyedRowDecodingThrowsTypeMismatch() async throws {
        try await runUsingTestDatabaseClient { database in
            struct UnkeyedValue: Decodable, Sendable {
                init(from decoder: Decoder) throws {
                    var container = try decoder.unkeyedContainer()
                    _ = try container.decode(String.self)
                }
            }

            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT 'value' AS "value";
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                do {
                    _ = try result[0]
                        .decode(
                            column: "value",
                            as: UnkeyedValue.self
                        )
                    Issue.record(
                        "Expected unkeyed decoding to throw a type mismatch."
                    )
                }
                catch let DecodingError.typeMismatch(_, context) {
                    #expect(
                        context.debugDescription.contains(
                            "Unkeyed decoding is not supported."
                        )
                    )
                }
                catch {
                    Issue.record(
                        "Expected a typeMismatch error for unkeyed decoding."
                    )
                }
            }
        }
    }

    @Test
    func queryFailureErrorText() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                do {
                    _ = try await connection.run(
                        query: #"""
                            SELECT *
                            FROM "missing_table";
                            """#
                    )
                    Issue.record("Expected query to fail for missing table.")
                }
                catch DatabaseError.query(let error) {
                    #expect("\(error)".contains("no such table"))
                }
                catch {
                    Issue.record("Expected database query error to be thrown.")
                }
            }
        }
    }

    @Test
    func versionCheck() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                let result = try await connection.run(
                    query: #"""
                        SELECT
                            sqlite_version() AS "version"
                        WHERE
                            1=\#(1);
                        """#
                ) { try await $0.collect() }

                #expect(result.count == 1)

                let item = result[0]
                let version = try item.decode(
                    column: "version",
                    as: String.self
                )
                #expect(version.split(separator: ".").count == 3)
            }
        }
    }

    @Test
    func rowSequenceIteratesRowsInOrder() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS "planets" (
                            "id" INTEGER PRIMARY KEY,
                            "name" TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "planets" ("id", "name")
                        VALUES
                            (1, 'Mercury'),
                            (2, 'Venus');
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT *
                        FROM "planets"
                        ORDER BY "id" ASC;
                        """#
                )

                var iterator = sequence.makeAsyncIterator()

                let first = await iterator.next()
                #expect(first != nil)
                #expect(
                    try first?.decode(column: "name", as: String.self)
                        == "Mercury"
                )

                let second = await iterator.next()
                #expect(second != nil)
                #expect(
                    try second?.decode(column: "name", as: String.self)
                        == "Venus"
                )

                let third = await iterator.next()
                #expect(third == nil)
            }
        }
    }

    @Test
    func rowSequenceCollectReturnsAllRows() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS "greetings" (
                            "id" INTEGER PRIMARY KEY,
                            "name" TEXT
                        );
                        """#
                )

                try await connection.run(
                    query: #"""
                        INSERT INTO "greetings" ("id", "name")
                        VALUES
                            (1, 'Hello'),
                            (2, 'World');
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT
                            "id",
                            "name"
                        FROM "greetings"
                        ORDER BY "id" ASC;
                        """#
                )

                let rows = try await sequence.collect()
                #expect(rows.count == 2)

                let firstName = try rows[0]
                    .decode(
                        column: "name",
                        as: String.self
                    )
                let secondName = try rows[1]
                    .decode(
                        column: "name",
                        as: String.self
                    )

                #expect(firstName == "Hello")
                #expect(secondName == "World")
            }
        }
    }

    @Test
    func rowSequenceHandlesEmptyResults() async throws {
        try await runUsingTestDatabaseClient { database in
            try await database.withConnection { connection in
                try await connection.run(
                    query: #"""
                        CREATE TABLE IF NOT EXISTS "empty_rows" (
                            "id" INTEGER PRIMARY KEY,
                            "name" TEXT
                        );
                        """#
                )

                let sequence = try await connection.run(
                    query: #"""
                        SELECT
                            "id",
                            "name"
                        FROM "empty_rows"
                        WHERE
                            1=0;
                        """#
                )

                let rows = try await sequence.collect()
                #expect(rows.isEmpty)

                var iterator = sequence.makeAsyncIterator()
                let first = await iterator.next()
                #expect(first == nil)
            }
        }
    }

}

#if ServiceLifecycle
import ServiceLifecycle

extension FeatherDatabaseSQLiteTestSuite {

    @Test
    func basicServiceLifecycleSupport() async throws {
        var logger = Logger(label: "test")
        logger.logLevel = .info

        let configuration = SQLiteClient.Configuration(
            storage: .memory,
        )
        let client = SQLiteClient(configuration: configuration)
        let database = DatabaseClientSQLite(client: client)
        let service = DatabaseServiceSQLite(client)

        let serviceGroup = ServiceGroup(
            services: [service],
            logger: logger
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await serviceGroup.run()
            }
            group.addTask {
                let result = try await database.withConnection { connection in
                    try await connection.run(
                        query: #"""
                            SELECT 
                                sqlite_version() AS "version" 
                            WHERE 
                                1=\#(1);
                            """#
                    )
                }

                let resultArray = try await result.collect()
                #expect(resultArray.count == 1)

                let item = resultArray[0]
                let version = try item.decode(
                    column: "version",
                    as: String.self
                )
                #expect(version.split(separator: ".").count == 3)
            }
            try await group.next()

            try await Task.sleep(for: .milliseconds(100))

            await serviceGroup.triggerGracefulShutdown()
        }
    }

    @Test
    func serviceLifecycleCancellationShutsDownClient() async throws {
        let configuration = SQLiteClient.Configuration(
            storage: .memory
        )
        let client = SQLiteClient(configuration: configuration)
        let service = DatabaseServiceSQLite(client)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await service.run()
            }

            try await Task.sleep(for: .milliseconds(100))
            group.cancelAll()

            do {
                while let _ = try await group.next() {}
            }
            catch {
                // Cancellation is expected; the shutdown is asserted below.
            }
        }

        do {
            try await client.withConnection { _ in }
            Issue.record("Expected shutdown to reject new connections.")
        }
        catch {
            #expect(error is SQLiteConnectionPoolError)
        }
    }

    @Test
    func serviceLifecycleGracefulShutdownShutsDownClient() async throws {
        var logger = Logger(label: "test")
        logger.logLevel = .info

        let configuration = SQLiteClient.Configuration(
            storage: .memory
        )
        let client = SQLiteClient(configuration: configuration)
        let service = DatabaseServiceSQLite(client)
        let serviceGroup = ServiceGroup(
            services: [service],
            logger: logger
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await serviceGroup.run()
            }

            try await Task.sleep(for: .milliseconds(100))
            await serviceGroup.triggerGracefulShutdown()

            do {
                while let _ = try await group.next() {}
            }
            catch {
                Issue.record(error)
            }
        }

        do {
            try await client.withConnection { _ in }
            Issue.record("Expected shutdown to reject new connections.")
        }
        catch {
            #expect(error is SQLiteConnectionPoolError)
        }
    }

    @Test
    func cancellationErrorTrigger() async throws {
        var logger = Logger(label: "test")
        logger.logLevel = .info

        let configuration = SQLiteClient.Configuration(
            storage: .memory
        )
        let client = SQLiteClient(configuration: configuration)
        let database = DatabaseClientSQLite(
            client: client
        )

        enum MigrationError: Error {
            case generic
        }

        struct MigrationService: Service {
            let database: any DatabaseClient

            func run() async throws {
                let result = try await database.withConnection { connection in
                    try await connection.run(
                        query: #"""
                            SELECT sqlite_version() AS "version"
                            """#
                    ) { try await $0.collect().first }
                }
                let version = try result?
                    .decode(
                        column: "version",
                        as: String.self
                    )
                #expect(version?.split(separator: ".").count == 3)

                throw MigrationError.generic
            }
        }

        let serviceGroup = ServiceGroup(
            configuration: .init(
                services: [
                    .init(
                        service: DatabaseServiceSQLite(client)
                    ),
                    .init(
                        service: MigrationService(database: database),
                        successTerminationBehavior: .gracefullyShutdownGroup,
                        failureTerminationBehavior: .cancelGroup
                    ),
                ],
                logger: logger
            )
        )

        do {
            try await serviceGroup.run()
            Issue.record("Service group should fail.")
        }
        catch let error as MigrationError {
            #expect(error == .generic)
        }
        catch {
            Issue.record("Service group should throw a generic Migration error")
        }
    }

    @Test
    func serviceGracefulShutdown() async throws {
        var logger = Logger(label: "test")
        logger.logLevel = .info

        let configuration = SQLiteClient.Configuration(
            storage: .memory
        )
        let client = SQLiteClient(configuration: configuration)
        let service = DatabaseServiceSQLite(client)

        try await testGracefulShutdown { trigger in
            try await withThrowingTaskGroup { group in
                let serviceGroup = ServiceGroup(
                    services: [service],
                    logger: logger
                )
                group.addTask { try await serviceGroup.run() }

                trigger.triggerGracefulShutdown()

                try await group.waitForAll()
            }
        }
    }
}
#endif
