# 2026.11.07-1 – Første GitHub-utgave

Første utgave i nytt repository, med siste fungerende p24r16 som teknisk grunnlag.

- Datoversjon ÅÅÅÅ.MM.DD-N samordnes i applikasjon, databaseforventninger, HA-kontrakt, frontendpublisering og leveransemetadata.
- README, overlevering og AGENTS.md beskriver gjeldende arkitektur og arbeidsmåte. Direkte arbeid på main etter avklaring og «start»; issues/PR inngår ikke i prosessen.
- Konkrete faglige nettlenker videreføres i W-34/70-faggrunnlaget. De er kildekandidater, ikke automatisk belegg for aktive terskler.
- Pakkebyggingen fungerer fra Git-checkout og lager versjonert ZIP/SHA uten Git-metadata, lokale driftsfiler eller tidligere bygg.
- Ytelsestestens klokkefremrykk bruker Unix-tid og DB-policy uavhengig av sesjonstidssone; runtime-logikken er uendret.
- MIT-lisensen fra det nye repositoryet er bevart. Releasejobben kontrollerer og publiserer ZIP og SHA for kildecommitten.

MariaDB 12.3.3, Node-RED 5.0.7, HA-plugin 0.80.3 og mysql-palett 3.0.4 videreføres. Runtime-schema er 9 og template-schema 4. Se TEST-RESULTS.md for faktisk testomfang og åpne måltester.

**Installeren resetter fortsatt databasen. Utgaven er ikke en databevarende produksjonsoppgradering.** Eksporter sesjoner/templates som skal beholdes før tilsiktet installasjon. Neste avgrensede arbeid er et oppgraderingsløp med bevaring av data.
