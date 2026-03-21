-- ============================================================
-- Script d'initialisation PostgreSQL – Gestion Crédit Pro
-- Exécuter UNE SEULE FOIS sur un serveur vierge
-- ============================================================

CREATE DATABASE gestion_credit_pro
    WITH ENCODING 'UTF8'
    LC_COLLATE = 'fr_CI.UTF-8'
    LC_CTYPE = 'fr_CI.UTF-8';

\c gestion_credit_pro;

-- Extension UUID native PostgreSQL
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Index pour les recherches fréquentes
-- (Flask-Migrate crée les tables, ces index optimisent les requêtes)

-- Après flask db upgrade, exécuter ces index :
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_contrats_client_statut
    ON contrats_credit(client_id, statut);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_contrats_commercant_statut
    ON contrats_credit(commercant_id, statut);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_contrats_echeance
    ON contrats_credit(date_echeance)
    WHERE statut = 'ACTIF';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_clients_telephone
    ON clients(telephone);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scores_client
    ON scores_reputation(client_id, score_global);

-- Vue analytique pour le tableau de bord commerçant
CREATE OR REPLACE VIEW vue_dashboard_commercant AS
SELECT
    c.commercant_id,
    COUNT(*) FILTER (WHERE c.statut = 'ACTIF') AS contrats_actifs,
    COUNT(*) FILTER (WHERE c.statut = 'EN_RETARD') AS contrats_retard,
    COUNT(*) FILTER (WHERE c.statut = 'SOLDE') AS contrats_soldes,
    SUM(c.montant_restant) FILTER (WHERE c.statut IN ('ACTIF', 'EN_RETARD')) AS encours_total,
    SUM(c.montant_rembourse) AS total_rembourse,
    AVG(c.score_au_moment_octroi) AS score_moyen_clients
FROM contrats_credit c
GROUP BY c.commercant_id;
