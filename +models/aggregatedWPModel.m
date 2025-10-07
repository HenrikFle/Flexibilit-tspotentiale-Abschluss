function wpAgg_kW = aggregatedWPModel(singleWP_kW, numWP, dtHours)
% aggregatedWPModel  Aggregiert mehrere Wärmepumpenprofile stochastisch
% -------------------------------------------------------------------------
%  Diese Funktion simuliert das aggregierte Lastprofil von numWP 
%  Wärmepumpen, indem jedes Einzelprofil um einen zufälligen Zeitversatz 
%  verschoben und anschließend aufsummiert wird.
%
%  Inputs:
%    singleWP_kW : [n×1] Vektor mit der Leistung einer einzelnen Wärmepumpe (kW)
%    numWP       : Anzahl der Wärmepumpen im Quartier (integer ≥ 1)
%    dtHours     : Zeitschrittlänge in Stunden (z. B. 0.25 für 15 Minuten)
%
%  Output:
%    wpAgg_kW    : [n×1] Aggregiertes Leistungssignal aller numWP WP (kW)
%
%  Vorgehensweise:
%    1. Bestimme die Anzahl der Zeitschritte n = length(singleWP_kW).
%    2. Berechne den maximalen Versatz in Samples, der ±4 Stunden entspricht:
%         offsetMax = round(4 / dtHours).
%    3. Wähle für jede WP einen Normal-verteilen Offset (in Samples) mit
%       σ = offsetMax / 3, so dass ±3σ ≈ ±offsetMax.
%    4. Runde die Offsets und beschränke sie auf [–offsetMax, +offsetMax].
%    5. Verschiebe das Einzelprofil mit circshift um den jeweiligen Offset.
%    6. Füge alle verschobenen Profile zeilenweise zusammen.
%
%  Hinweis:
%    - Die Zufalls-Initialisierung (rng) wird hier auf 'shuffle' gestellt, 
%      damit bei jedem Aufruf andere Offsets entstehen. Für reproduzierbare 
%      Resultate kann man stattdessen rng(seed) verwenden.
%
%  Beispiel:
%    singleProfile = [0; 1.2; 2.1; 1.8; ...];  % 15-Min-Daten einer WP
%    aggregated = aggregatedWPModel(singleProfile, 10, 0.25);
%    % 'aggregated' enthält dann das summierte Profil von 10 WP.
%
%  Autor: ChatGPT (revidiert)
%  Datum: 04-Juni-2025
% -------------------------------------------------------------------------

    % Anzahl Zeitschritte der Simulation
    n = numel(singleWP_kW);

    % Falls nur eine WP vorhanden ist, direkt das Einzelprofil zurückgeben
    if numWP <= 1
        wpAgg_kW = singleWP_kW;
        return;
    end

    % Höhe des maximalen Versatzes in Samples (±4 Stunden)
    offsetMax = round(4 / dtHours);

    % Standardabweichung für Normalverteilung, so dass ±3σ ≈ ±offsetMax
    sigma = offsetMax / 3;

    % Zufalls-Offsets erzeugen (Normalverteilt mit Mittelwert 0, Varianz σ^2)
    rng('shuffle');  % Für unterschiedliche Ergebnisse bei jedem Durchlauf
    rawOffsets = sigma * randn(numWP, 1);
    offsets = round(rawOffsets);

    % Auf [-offsetMax, +offsetMax] beschränken
    offsets = max(min(offsets, offsetMax), -offsetMax);

    % Matrix zum Sammeln aller verschobenen Einzelprofile
    wpMat = zeros(n, numWP);

    for i = 1:numWP
        shiftBy = offsets(i);
        % circshift rotiert das Profil um 'shiftBy' Zeitschritte
        wpMat(:, i) = circshift(singleWP_kW, shiftBy);
    end

    % Aufsummieren aller verschobenen Profile
    wpAgg_kW = sum(wpMat, 2);

    % Optional: Wenn durchschnittliches Profil gewünscht, durch numWP teilen:
    % wpAgg_kW = wpAgg_kW / numWP;
end
