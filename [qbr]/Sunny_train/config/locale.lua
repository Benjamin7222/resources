-- ============================================================================
--  Sunny_train - Textes (FR)
--  Toutes les chaînes affichées au joueur passent par Sunny.L('clé', ...).
--  Les chaînes acceptent le format string.format (%s, %d...).
-- ============================================================================

Sunny = Sunny or {}

Sunny.Locale = {
    -- Génériques
    error_generic         = 'Le télégraphe ne répond pas. Réessayez.',
    error_busy            = 'Patientez un instant...',
    error_no_permission   = "Vous n'êtes pas habilité à cette opération.",
    error_not_employee    = 'Registre réservé au personnel. Job lu : « %s » grade %d — autorisés : %s.',
    error_not_loaded      = 'Personnage non chargé.',
    error_too_far         = 'Vous êtes trop loin du guichet.',
    error_not_on_service  = 'Action réservée aux cheminots.',
    error_invalid         = 'Demande invalide.',

    -- Service

    -- Runs / missions
    run_already_active    = 'Vous avez déjà un ordre de mission en cours.',
    run_train_unavailable = "Ce train n'est pas disponible.",
    run_train_in_use      = 'Ce train est déjà en circulation.',
    run_train_state       = 'Ce train est « %s » et ne peut pas circuler.',
    run_mission_invalid   = 'Cet ordre de mission est invalide pour ce train.',
    run_wrong_station     = 'Ce départ se fait depuis la gare de %s.',
    run_cooldown          = 'La compagnie ne vous confie pas de nouvelle mission avant %d s.',
    run_spawn_failed      = "Le train n'a pas pu être mis en voie.",
    run_started           = 'Ordre de mission signé : %s. Le train est à quai.',
    run_next_station      = 'Prochain arrêt : %s',
    run_arrived_station   = 'Arrêt en gare de %s — départ autorisé dans %d s.',
    run_depart_allowed    = 'Départ autorisé vers %s.',
    run_terminus          = 'Terminus : %s. Terminez le trajet pour clore la mission.',
    run_finished          = 'Mission terminée. Prime versée : $%s',
    run_finished_free     = 'Trajet terminé. Merci pour votre service.',
    run_cancelled         = 'Ordre de mission annulé.',
    run_failed            = 'Mission échouée : %s',
    run_too_fast          = 'Horaire incohérent : arrêt refusé par la compagnie.',
    run_not_at_station    = "Le train n'est pas à quai.",
    run_train_lost        = 'Le train a été perdu.',
    run_timeout           = 'Délai de la mission dépassé.',
    run_no_active         = "Aucun ordre de mission en cours.",

    -- Conduite
    drive_notch           = 'Régulateur : %s',
    drive_locked          = 'Train immobilisé.',

    -- Voyage libre
    free_label            = 'Voyage libre',
    free_started          = 'Train mis en voie à destination de %s. Bon voyage !',
    free_parked           = 'Train rangé. Merci pour ce voyage.',
    free_parked_auto      = 'Train rangé automatiquement : cabine abandonnée.',
    park_too_far          = "Rangez le train au dépôt ou au quai d'une gare.",
    free_no_depot         = "Cette gare n'a pas de dépôt : aucun train ne peut y être mis en voie.",
    free_invalid_dest     = 'Destination injoignable par le réseau.',
    free_arrived          = 'Arrivée à %s. Rangez le train quand vous le souhaitez.',
    free_disabled         = 'Les voyages libres sont désactivés.',

    -- Flotte & wagons
    fleet_not_owned       = "La compagnie ne possède pas ce train.",
    fleet_already_owned   = "La compagnie possède déjà ce train.",
    fleet_no_funds        = "Fonds insuffisants : %s $ nécessaires.",
    fleet_bought          = "%s acquis pour %s $. Bienvenue dans la flotte !",
    fleet_sold            = "%s revendu pour %s $.",
    fleet_cannot_sell     = "Ce train ne peut pas être revendu.",
    hold_busy             = "Le wagon est ouvert par un autre employé.",
    hold_too_far          = "Rendez-vous au dépôt d'une gare ou près du train.",
    hold_missing_cargo    = "Cargaison incomplète dans le wagon : %s.",
    fuel_min              = "Il faut au moins %d × %s dans le wagon pour partir.",
    fuel_empty            = "Plus de charbon : chargez-en dans le wagon du train, il est immobilisé.",
    fuel_ok               = "Charbon chargé (%d). La machine repart.",
    admin_despawned       = "Train retiré par un administrateur.",
    admin_despawn_done    = "%d train(s) Sunny_train retiré(s).",

    -- Départs programmés
    dep_created           = 'Départ programmé : %s → %s à %s.',
    dep_cancelled         = 'Départ de %s annulé.',
    dep_invalid           = 'Départ invalide ou déjà pris en charge.',
    dep_bad_time          = 'Horaire invalide : choisissez un horaire proposé.',
    dep_limit             = 'Vous avez déjà %d départs programmés en attente.',
    dep_slot_taken        = 'Un départ est déjà programmé à %s depuis cette gare.',
    dep_in_progress       = 'Un train est déjà à quai pour ce départ.',
    dep_wrong_train       = 'Ce départ est programmé avec le train « %s ».',
    ticket_no_departure   = 'Ce départ n\'est plus proposé à la vente.',


    -- Aiguillages
    junction_prompt       = 'Changer de voie : %s',
    junction_title        = 'Aiguillage à %d m — %s',
    junction_switched     = 'Aiguillage basculé : %s',
    junction_no_run       = 'Seul le conducteur d\'un convoi en circulation peut manœuvrer un aiguillage.',
    junction_invalid      = 'Aiguillage inconnu.',

    -- Billets
    ticket_bought         = 'Billet n°%s délivré pour %s.',
    ticket_no_money       = "Vous n'avez pas assez d'argent.",
    ticket_limit          = 'Vous avez déjà trop de billets valides.',
    ticket_inventory_full = 'Vous ne pouvez pas porter ce billet.',
    ticket_invalid_dest   = 'Destination non desservie depuis cette gare.',
    ticket_invalid_class  = 'Classe inconnue.',
    ticket_punched_notify = 'Votre billet n°%s a été poinçonné par le contrôleur.',

    -- Contrôle
    control_no_target     = 'Aucun voyageur à proximité.',
    control_target_far    = 'Le voyageur est trop éloigné.',
    control_notify_target = 'Un contrôleur vérifie vos titres de transport.',
    control_punched       = 'Billet poinçonné.',
    control_cannot_punch  = 'Ce billet ne peut pas être poinçonné.',

    -- Maintenance
    maint_inspected       = 'Inspection consignée au registre.',
    maint_missing_items   = 'Matériel manquant : %s',
    maint_repaired        = 'Réparation effectuée (+%d %%).',
    maint_need_inspection = 'Une inspection récente est requise avant réparation.',
    maint_not_depot       = "Cette opération doit se faire dans une gare équipée d'un dépôt.",
    maint_restored        = 'Train remis en service.',
    maint_restore_refused = 'État insuffisant pour une remise en service (%d %% requis).',
    maint_retired         = 'Train retiré du service.',
    maint_in_use          = 'Ce train est actuellement en circulation.',
    maint_full            = 'Ce train est déjà en parfait état.',

    -- Braquage
    rob_prompt            = 'Braquer le convoi',
    rob_started_robber    = 'Braquage en cours... tenez la position %d secondes.',
    rob_started_driver    = 'Le convoi est attaqué ! Le train est immobilisé.',
    rob_aborted           = 'Le braquage a échoué.',
    rob_aborted_driver    = 'Les assaillants ont été repoussés. Vous pouvez reprendre la route.',
    rob_success           = 'Butin récupéré : $%s',
    rob_run_continues     = 'Les braqueurs sont partis. Vous pouvez reprendre la route.',
    rob_run_failed        = 'Le convoi a été dévalisé.',
    rob_min_police        = "Il n'y a pas assez de forces de l'ordre en ville.",
    rob_cooldown          = 'Ce convoi ne peut pas être attaqué pour le moment.',
    rob_not_allowed       = 'Impossible de braquer ce convoi.',
    rob_need_weapon       = 'Il vous faut une arme en main.',
    rob_too_fast          = 'Le train roule trop vite.',

    -- Dispatch (repli si aucun dispatch n'est branché)
    dispatch_title        = 'TÉLÉGRAMME — Compagnie ferroviaire',
    dispatch_robbery      = 'Attaque du convoi « %s » près de %s !',

    -- Prompts
    prompt_office         = 'Compagnie ferroviaire',
    prompt_desk           = 'Départs et billets',
    prompt_open           = 'Ouvrir',
    prompt_finish         = 'Terminer le trajet',
    prompt_park           = 'Ranger le train',
}

--- Récupère un texte traduit.
---@param key string
---@param ... any
---@return string
function Sunny.L(key, ...)
    local text = Sunny.Locale[key]
    if not text then return key end
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        return ok and formatted or text
    end
    return text
end
