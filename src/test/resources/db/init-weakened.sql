-- A DELIBERATELY WEAKENED COPY of init.sql. Not used by any normal run.
--
-- Every constraint a negative scenario asserts on is removed here, except the foreign keys —
-- see the note at the bottom for why those are the one thing this technique cannot reach.
-- Booting the suite against this schema MUST make it fail: the scenario asserting 23505 on a
-- duplicate ISBN has had the unique index taken away, the ones asserting 23514 on an
-- out-of-range rating have lost their CHECK, and so on.
--
-- A negative test nobody has watched fail proves nothing. This file is how CI proves these ones
-- can — see the "Prove the negative tests can fail" job, which runs the suite against this
-- schema and treats a green result as the failure.
--
-- The exact set that must go red is in mutation-expectations.txt, and the job checks each entry
-- individually rather than settling for "something failed". One surviving failure would
-- otherwise satisfy the job while every other mutation quietly stopped being caught.
--
-- Keep in step with init.sql. Add a constraint there and a scenario asserting it, and weaken it
-- here, or the mutation job silently stops covering it.

CREATE SCHEMA IF NOT EXISTS api;

-- ----------------------------------------------------------------- authors

CREATE TABLE api.authors (
    id         serial PRIMARY KEY,
    -- NOT NULL removed ("an author with no name is rejected", 23502) and the CHECK removed
    -- ("a name that is only whitespace is rejected", 23514).
    "name"     text,
    -- NOT NULL removed: "an author with no country is rejected" asserts 23502.
    country    text,
    -- UNIQUE removed (duplicate email on create and on update, both 23505) and the format CHECK
    -- removed (the three malformed-address rows, 23514).
    email      text NOT NULL
);

-- ------------------------------------------------------------------- books

CREATE TABLE api.books (
    id         serial PRIMARY KEY,
    -- NOT NULL removed: "Creating a book without a required field is rejected" asserts 23502,
    -- which is precisely this constraint firing.
    title      text CHECK (length(btrim(title)) > 0),
    -- The foreign key STAYS. See the note at the bottom.
    "authorId" integer NOT NULL REFERENCES api.authors (id) ON DELETE CASCADE,
    -- UNIQUE removed: two scenarios assert 23505 on a duplicate ISBN, one on create and one on
    -- update.
    isbn       text NOT NULL CHECK (length(btrim(isbn)) = 13),
    -- CHECK removed: "a negative price is rejected" asserts 23514.
    "priceUsd" numeric(10, 2) NOT NULL,
    -- CHECK removed: "a book with no pages is rejected" asserts 23514.
    "pageCount" integer NOT NULL,
    published  date NOT NULL,
    "inPrint"  boolean NOT NULL DEFAULT true
);

-- ----------------------------------------------------------------- reviews

CREATE TABLE api.reviews (
    id         serial PRIMARY KEY,
    "bookId"   integer NOT NULL REFERENCES api.books (id) ON DELETE CASCADE,
    -- NOT NULL removed ("a review with no reviewer is rejected", 23502) and the CHECK removed
    -- ("a reviewer that is only whitespace is rejected", 23514).
    reviewer   text,
    -- CHECK removed: the rating outline asserts 23514 on 0, 6, -1 and 99, and a separate
    -- scenario asserts the same constraint holds on UPDATE.
    rating     integer NOT NULL,
    body       text NOT NULL DEFAULT ''
);

-- ----------------------------------------------------------------- indexes
--
-- Postgres indexes a PRIMARY KEY and a UNIQUE constraint automatically. It does not index the
-- referencing side of a FOREIGN KEY, which is the side every child lookup filters on — and the
-- one every embedded query joins on.
--
-- Found by reading a query plan at realistic volume rather than by timing anything. With fifty
-- thousand reviews, `/reviews?bookId=eq.500` was a Seq Scan costing 993 to return five rows;
-- with this index it is a Bitmap Heap Scan costing 22.67. The same plan against the eleven-row
-- seed showed nothing at all, which is exactly why db/volume.sql exists.
CREATE INDEX books_author_idx  ON api.books ("authorId");
CREATE INDEX reviews_book_idx  ON api.reviews ("bookId");

-- -------------------------------------------------------------------- seed

INSERT INTO api.authors (id, "name", country, email) VALUES
  (1, 'Ursula K. Le Guin', 'United States', 'ursula@example.com'),
  (2, 'Gabriel Garcia Marquez', 'Colombia',  'gabo@example.com'),
  (3, 'Italo Calvino',      'Italy',         'italo@example.com');
SELECT setval('api.authors_id_seq', 3, true);

INSERT INTO api.books (id, title, "authorId", isbn, "priceUsd", "pageCount", published, "inPrint") VALUES
  (1, 'The Left Hand of Darkness', 1, '9780441478125', 14.99, 304, '1969-03-01', true),
  (2, 'A Wizard of Earthsea',      1, '9780553383041', 11.50, 208, '1968-11-01', true),
  (3, 'One Hundred Years of Solitude', 2, '9780060883287', 16.00, 417, '1967-05-30', true),
  (4, 'Invisible Cities',          3, '9780156453806', 13.25, 165, '1972-01-01', false);
SELECT setval('api.books_id_seq', 4, true);

INSERT INTO api.reviews (id, "bookId", reviewer, rating, body) VALUES
  (1, 1, 'alex',  5, 'A thought experiment that never stops being one.'),
  (2, 1, 'sam',   4, 'Cold, in every sense.'),
  (3, 3, 'chris', 5, 'The family tree is the plot.'),
  (4, 4, 'robin', 4, 'Fifty-five cities, one city.');
SELECT setval('api.reviews_id_seq', 4, true);

-- --------------------------------------------------------- PostgREST roles

-- Anonymous callers may read and nothing else. Writing requires a JWT naming a role that has
-- been granted the privilege, which is the arrangement PostgREST is built around: the token
-- carries no permissions of its own, it names a Postgres role, and these grants decide what that
-- role can do. Authorisation lives in the schema, so it can be asserted on rather than mocked.
CREATE ROLE web_anon NOLOGIN;
GRANT USAGE ON SCHEMA api TO web_anon;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO web_anon;

-- A reader that is authenticated and still may not write. Worth having as its own role: a suite
-- that only tests "anonymous cannot write" leaves the far more common production bug untouched,
-- which is a valid token whose role was granted more than anyone intended.
CREATE ROLE catalog_reader NOLOGIN;
GRANT USAGE ON SCHEMA api TO catalog_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO catalog_reader;

CREATE ROLE catalog_writer NOLOGIN;
GRANT USAGE ON SCHEMA api TO catalog_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA api TO catalog_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA api TO catalog_writer;

CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'postgrest_pw';
GRANT web_anon TO authenticator;
GRANT catalog_reader TO authenticator;
GRANT catalog_writer TO authenticator;

-- ------------------------------------------------- why the keys are not touched
--
-- Two negative scenarios assert 23503 — a book against a missing author, and a review against a
-- missing book — and neither is covered by this file. Dropping those foreign keys would prove
-- they can fail, and would simultaneously delete the feature the rest of the suite is built on:
-- PostgREST derives its embeddable relationships from exactly these constraints, so without
-- them `/books?select=*,author:authors(*)` stops being a valid query and every scenario in
-- embedding.feature fails for an unrelated reason.
--
-- A mutation whose blast radius is the whole suite tells you nothing about the one assertion it
-- was aimed at. Recorded as a gap in mutation-expectations.txt rather than papered over.
