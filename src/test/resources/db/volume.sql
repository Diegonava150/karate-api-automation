-- Extra rows, layered on top of the real schema. Not used by any functional run.
--
-- Postgres runs everything in /docker-entrypoint-initdb.d in alphabetical order, so this arrives
-- as 02-volume.sql after the real 01-schema.sql. That is the whole reason it contains no DDL:
-- a third copy of the schema would be a third thing to keep in step, and the two that already
-- exist have to be reconciled by hand every time a constraint changes.
--
-- Why it exists at all. The ordinary seed is eleven rows, which is the right size for asserting
-- behaviour and the wrong size for asserting anything about cost — Postgres will decline to use
-- an index on a four-row table, correctly, so a plan taken against the normal fixture describes
-- a database nobody will ever run.
--
-- That is not hypothetical. The plan for the three-level embed against the eleven-row seed showed
-- `Seq Scan` at a cost of 48858 and looked exactly like a missing index. Adding indexes dropped
-- it to 7.53 — and so did dropping those indexes again while keeping the ANALYZE. The entire
-- difference was stale statistics. A plan assertion written against that fixture would have
-- pinned the wrong conclusion in place.

-- Deliberately modest: large enough that the planner stops preferring a sequential scan out of
-- indifference, small enough that the container still starts in seconds.

INSERT INTO api.authors ("name", country, email)
SELECT 'Author ' || i,
       'Country ' || (i % 20),
       'author' || i || '@example.com'
FROM generate_series(1, 500) AS i;

INSERT INTO api.books (title, "authorId", isbn, "priceUsd", "pageCount", published, "inPrint")
SELECT 'Book ' || i,
       -- Spread across the generated authors, skipping the three seeded ones so their embedded
       -- book lists stay the size the functional scenarios expect.
       4 + (i % 500),
       lpad(i::text, 13, '0'),
       ((i % 9000) + 99)::numeric / 100,
       50 + (i % 900),
       DATE '1900-01-01' + (i % 45000),
       (i % 7) <> 0
FROM generate_series(1, 10000) AS i;

INSERT INTO api.reviews ("bookId", reviewer, rating, body)
SELECT 5 + (i % 10000),
       'reviewer' || i,
       1 + (i % 5),
       ''
FROM generate_series(1, 50000) AS i;

-- Without this the planner works from the estimates it had when the tables were empty, and every
-- plan taken afterwards describes a database that does not exist. One line, and it is the
-- difference between a meaningful plan assertion and a misleading one.
ANALYZE api.authors;
ANALYZE api.books;
ANALYZE api.reviews;
