-- =====================================================================
-- S1 · M2 · 01_ddl.sql : création des trois couches
--   reception : copie brute (tout en texte) -> aucun rejet à l'import
--   rejets    : journal des lignes écartées + cause
--   metier    : modèle relationnel typé et contraint
-- Rejouable : DROP SCHEMA ... CASCADE puis recréation.
-- =====================================================================
\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS metier    CASCADE;
DROP SCHEMA IF EXISTS rejets    CASCADE;
DROP SCHEMA IF EXISTS reception CASCADE;
CREATE SCHEMA reception;
CREATE SCHEMA rejets;
CREATE SCHEMA metier;

-- ---------------------------------------------------------------------
-- Couche RECEPTION : tout en text, ligne_no = rang dans le fichier
-- (hors en-tête), source_file et charge_le pour la traçabilité.
-- ---------------------------------------------------------------------
CREATE TABLE reception.categories_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_id text, category_name text, parent_category_id text,
  source_file text NOT NULL DEFAULT 'categories.csv',
  charge_le timestamptz NOT NULL DEFAULT now());

CREATE TABLE reception.products_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id text, sku text, product_name text, category_id text, first_listed_on text,
  source_file text NOT NULL DEFAULT 'products.csv',
  charge_le timestamptz NOT NULL DEFAULT now());

CREATE TABLE reception.customers_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id text, customer_name text, city text,
  source_file text NOT NULL DEFAULT 'customers.csv',
  charge_le timestamptz NOT NULL DEFAULT now());

CREATE TABLE reception.orders_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id text, customer_id text, ordered_on text, status text,
  source_file text NOT NULL DEFAULT 'orders.csv',
  charge_le timestamptz NOT NULL DEFAULT now());

CREATE TABLE reception.order_items_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_item_id text, order_id text, product_id text, quantity text, unit_price_cents text,
  source_file text NOT NULL DEFAULT 'order_items.csv',
  charge_le timestamptz NOT NULL DEFAULT now());

-- NDJSON : une ligne de fichier = une valeur text (un JSON invalide
-- n'empêche donc pas la réception, il sera rejeté à l'intégration).
CREATE TABLE reception.payments_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ligne text,
  source_file text NOT NULL DEFAULT 'payments.ndjson',
  charge_le timestamptz NOT NULL DEFAULT now());

-- ---------------------------------------------------------------------
-- Couche REJETS : une ligne = un enregistrement source écarté
-- ---------------------------------------------------------------------
CREATE TABLE rejets.journal (
  rejet_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_file  text   NOT NULL,
  ligne_no     bigint NOT NULL,
  cle_source   text,
  motif        text   NOT NULL,
  contenu_brut text   NOT NULL,
  detecte_le   timestamptz NOT NULL DEFAULT now());

-- ---------------------------------------------------------------------
-- Couche METIER (montants en centimes, entiers : pas d'arrondi flottant)
-- ---------------------------------------------------------------------
CREATE TABLE metier.categories (
  category_id        integer PRIMARY KEY,
  category_name      text NOT NULL,
  parent_category_id integer REFERENCES metier.categories (category_id));

CREATE TABLE metier.products (
  product_id      integer PRIMARY KEY,
  sku             text NOT NULL UNIQUE,
  product_name    text NOT NULL,
  category_id     integer NOT NULL REFERENCES metier.categories (category_id),
  first_listed_on date NOT NULL);

CREATE TABLE metier.customers (
  customer_id   integer PRIMARY KEY,
  customer_name text NOT NULL,
  city          text NOT NULL);

CREATE TABLE metier.orders (
  order_id    integer PRIMARY KEY,
  customer_id integer NOT NULL REFERENCES metier.customers (customer_id),
  ordered_on  date    NOT NULL,
  status      text    NOT NULL CHECK (status IN ('completed','pending','cancelled')));

CREATE TABLE metier.order_items (
  order_item_id    integer PRIMARY KEY,
  order_id         integer NOT NULL REFERENCES metier.orders (order_id),
  product_id       integer NOT NULL REFERENCES metier.products (product_id),
  quantity         integer NOT NULL CHECK (quantity > 0),
  unit_price_cents integer NOT NULL CHECK (unit_price_cents > 0));

CREATE TABLE metier.payments (
  payment_id   integer PRIMARY KEY,
  order_id     integer NOT NULL REFERENCES metier.orders (order_id),
  paid_on      date    NOT NULL,
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  status       text    NOT NULL CHECK (status IN ('captured','pending')));

-- Index sur les clés étrangères (PostgreSQL n'en crée pas automatiquement)
CREATE INDEX orders_customer_idx      ON metier.orders      (customer_id);
CREATE INDEX order_items_order_idx    ON metier.order_items (order_id);
CREATE INDEX order_items_product_idx  ON metier.order_items (product_id);
CREATE INDEX payments_order_idx       ON metier.payments    (order_id);
CREATE INDEX products_category_idx    ON metier.products    (category_id);

COMMENT ON TABLE metier.order_items IS 'Grain : une ligne d''article. Montant ligne = quantity * unit_price_cents (prix au moment de la transaction).';
COMMENT ON TABLE metier.payments    IS 'Grain : une opération de paiement. Une commande peut en avoir plusieurs (paiement fractionné).';
COMMENT ON TABLE metier.orders      IS 'Grain : une commande. Pivot entre lignes d''articles et paiements : ne jamais joindre lignes et paiements directement.';

