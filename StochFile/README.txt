### README: file utile per riassumere i principali parametri della simulazione e dove è possibile modificarli

# Lanciare il file "main.jl" per eseguire una completa simulazione dei modelli CO e NC

# Utenti considerati: all'interno del file "energy_community_model.yml" è possibile modificare in "general:user_set" l'insieme degli utenti della EC e vedere quali risorse ciascun utente può installare

# Numero di scenari s ed epsilon per la prima ottimizzazione stocastica: nel file "main.jl" nelle righe 51-52 è possibile definire tali parametri

# Numero di scenari s per la prima risimulazione (dimensionamento fissato per ottenere dispacciamento previsionale): modificabile nel file "main.jl" alla riga 111

# Numero di scenari epsilon su cui risimulare ciascuno scenario s (dimensionamento e dispacciamento previsionale fissati): modificabile nel file "main.jl" alla riga 163

## PRINCIPALI MODELLI OTTIMIZZATI: (#NOTA: per modificare i parametri di ottimizzazione, i.e. primal_gap,time_limit,n_thread, dopo ciascun modello è presente una funzione set_parameters_ECmodel!() in cui è possibile indicare i valori desiderati)

# EC_NonCooperative (riga 83): modello stocastico non cooperativo con un numero di scenari s ed epsilon stabiliti come spiegato sopra

# EC_Cooperative (riga 95): modello stocastico cooperativo con un numero di scenari s ed epsilon stabiliti come spiegato sopra

# EC_NonCooperative_ris (riga 132): modello stocastico non cooperativo a dimensionamento fissato con un unico scenario s e un numero di scenari epsilon congruo a quanto sopra

# EC_Cooperative_ris (riga 146): modello stocastico cooperativo a dimensionamento fissato con un unico scenario s e un numero di scenari epsilon congruo a quanto sopra

# EC_NonCooperative_MC(riga 175): modello deterministico non cooperativo (solo uno scenario s e uno epsilon) a dimensionamento e dispacciamento previsionale fissati usato nel metodo Monte Carlo

# EC_Cooperative_MC(riga 191): modello deterministico cooperativo (solo uno scenario s e uno epsilon) a dimensionamento e dispacciamento previsionale fissati usato nel metodo Monte Carlo