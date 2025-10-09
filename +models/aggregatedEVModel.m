% Datei: +models/aggregatedEVModel.m
function [pEV_total, SoCvec, pEV_groups, SoC_groups] = aggregatedEVModel( ...
    resNoBatt_kW, dt, numEV, pMaxEV_kW, capacityEV_kWh, ...
    flexLowerBoundVec, flexUpperBoundVec)
% aggregatedEVModel.m
% -------------------------------------------------------------------------
% Gruppen A–D | Lade-/Entlade-Strategie:
%   • Notfall-Laden bis 40 %
%   • PV-Überschuss-Laden bis 90 %
%   • Basalladen bis 70 %, begrenzt durch flexUpperBoundVec
%   • V2G-Entladen (Bereich flexLowerBoundVec ≤ ΔP ≤ flexUpperBoundVec)
%       – nur solange SoC > 70 %
%       – max. so viel, dass Residuallast ≥ flexLowerBoundVec bleibt
%   • V2G-Entladen bei hoher Last  (ΔP ≥ flexUpperBoundVec)
% -------------------------------------------------------------------------

% ---------- Konstanten & Hilfsgrößen -------------------------------------
nSteps = length(resNoBatt_kW);

pA=0.3; pB=0.25; pC=0.3; pD=0.15;

capA = capacityEV_kWh*pA; maxA = pMaxEV_kW*pA;
capB = capacityEV_kWh*pB; maxB = pMaxEV_kW*pB;
capC = capacityEV_kWh*pC; maxC = pMaxEV_kW*pC;
capD = capacityEV_kWh*pD; maxD = pMaxEV_kW*pD;

emergencyFactor = 0.25;
emergA = emergencyFactor * maxA;
emergB = emergencyFactor * maxB;
emergC = emergencyFactor * maxC;
emergD = emergencyFactor * maxD;


dailyCons = (2250/365)*numEV;          % Fahrverbrauch

rateA = pA*dailyCons/(15-6);

rateB = pB*dailyCons/(24-(17-8));

rateC = pC*dailyCons/(18-9);

rateD = pD*dailyCons/6;



minSOC   = 0.40;    % Notfall-Ladegrenze

basalSOC = 0.70;    % Basalladen-Ziel

maxSOC   = 0.90;    % maximaler Lade-SoC

v2gSOC   = 0.70;    % neue Entladeschwelle (≥ 70 %)

% ---------- Speichergrößen ----------------------------------------------
pEV_A = zeros(nSteps,1); pEV_B = pEV_A; pEV_C = pEV_A; pEV_D = pEV_A;
SoC_A=0.5; SoC_B=0.5; SoC_C=0.5; SoC_D=0.5;
SoC_A_vec = zeros(nSteps,1); SoC_B_vec = SoC_A_vec;
SoC_C_vec = SoC_A_vec;       SoC_D_vec = SoC_A_vec;

flexLowerBoundVec = flexLowerBoundVec(:);
flexUpperBoundVec = flexUpperBoundVec(:);

if length(flexLowerBoundVec) ~= nSteps || length(flexUpperBoundVec) ~= nSteps
    error('aggregatedEVModel:BoundsLengthMismatch', ...
        'flexLowerBoundVec/flexUpperBoundVec müssen Länge %d haben.', nSteps);
end

% ---------- Haupt-Zeitschleife ------------------------------------------
for i = 1:nSteps
    deltaP = resNoBatt_kW(i);           % aktuelle Residuallast
    lower  = flexLowerBoundVec(i);
    upper  = flexUpperBoundVec(i);
    t      = mod((i-1)*dt,24);

    if isnan(lower)
        lower = deltaP;
    end
    if isnan(upper)
        upper = deltaP;
    end

    % Verfügbarkeiten & Fahrphasen ---------------------------------------
    availA = (t<6)||(t>=15);
    availB = (t>=8)&&(t<17);
    availC = (t<9)||(t>=18);
    availD = ~(((t>=7)&&(t<10))||((t>=15)&&(t<18)));

    driveA = ~availA; driveB = ~availB; driveC = ~availC; driveD = ~availD;
    SoC_A = max(SoC_A-driveA*rateA*dt/capA,0);
    SoC_B = max(SoC_B-driveB*rateB*dt/capB,0);
    SoC_C = max(SoC_C-driveC*rateC*dt/capC,0);
    SoC_D = max(SoC_D-driveD*rateD*dt/capD,0);

    isSurplus = deltaP <= lower;

    % ---------- 1) Notfall-Laden ----------------------------------------
    % Läuft nur außerhalb echter Überschussphasen, damit bei ΔP ≤ lower
    % die dort verfügbare Leistung ohne Notfall-Drossel genutzt werden kann.
    if ~isSurplus
        if availA&&SoC_A<minSOC
            E=min((minSOC-SoC_A)*capA, emergA*dt);
            if E>0
                pEV_A(i)=pEV_A(i)-E/dt;  SoC_A=SoC_A+E/capA;
            end
        end
        if availB&&SoC_B<minSOC
            E=min((minSOC-SoC_B)*capB, emergB*dt);
            if E>0
                pEV_B(i)=pEV_B(i)-E/dt;  SoC_B=SoC_B+E/capB;
            end
        end
        if availC&&SoC_C<minSOC
            E=min((minSOC-SoC_C)*capC, emergC*dt);
            if E>0
                pEV_C(i)=pEV_C(i)-E/dt;  SoC_C=SoC_C+E/capC;
            end
        end
        if availD&&SoC_D<minSOC
            E=min((minSOC-SoC_D)*capD, emergD*dt);
            if E>0
                pEV_D(i)=pEV_D(i)-E/dt;  SoC_D=SoC_D+E/capD;
            end
        end
    end


    % ---------- 2) PV-Überschuss-Laden ----------------------------------

    if isSurplus
        excess = max(lower - deltaP, 0);               % [kW]
        w=[pA*availA pB*availB pC*availC pD*availD];
        if sum(w)>0
            share=w/sum(w)*excess;                     % Aufteilung
            if availA&&SoC_A<maxSOC
                P=min(share(1),maxA);
                E=min(P*dt, (maxSOC-SoC_A)*capA);
                pEV_A(i)=pEV_A(i)-E/dt; SoC_A=SoC_A+E/capA; end
            if availB&&SoC_B<maxSOC
                P=min(share(2),maxB);
                E=min(P*dt, (maxSOC-SoC_B)*capB);
                pEV_B(i)=pEV_B(i)-E/dt; SoC_B=SoC_B+E/capB; end
            if availC&&SoC_C<maxSOC
                P=min(share(3),maxC);
                E=min(P*dt, (maxSOC-SoC_C)*capC);
                pEV_C(i)=pEV_C(i)-E/dt; SoC_C=SoC_C+E/capC; end
            if availD&&SoC_D<maxSOC
                P=min(share(4),maxD);
                E=min(P*dt, (maxSOC-SoC_D)*capD);
                pEV_D(i)=pEV_D(i)-E/dt; SoC_D=SoC_D+E/capD; end
        end

    % ---------- 3) Basalladen (Laden) -----------------------------------
    elseif deltaP>lower && deltaP<upper
        headroom = max(upper - deltaP, 0);                   % noch „frei” bis Obergrenze
        if availA&&SoC_A<basalSOC&&headroom>0
            P=min(maxA, headroom);
            E=min(P*dt, (basalSOC-SoC_A)*capA);
            pEV_A(i)=pEV_A(i)-E/dt; SoC_A=SoC_A+E/capA; headroom=headroom-P; end
        if availB&&SoC_B<basalSOC&&headroom>0
            P=min(maxB, headroom);
            E=min(P*dt, (basalSOC-SoC_B)*capB);
            pEV_B(i)=pEV_B(i)-E/dt; SoC_B=SoC_B+E/capB; headroom=headroom-P; end
        if availC&&SoC_C<basalSOC&&headroom>0
            P=min(maxC, headroom);
            E=min(P*dt, (basalSOC-SoC_C)*capC);
            pEV_C(i)=pEV_C(i)-E/dt; SoC_C=SoC_C+E/capC; headroom=headroom-P; end
        if availD&&SoC_D<basalSOC&&headroom>0
            P=min(maxD, headroom);
            E=min(P*dt, (basalSOC-SoC_D)*capD);
            pEV_D(i)=pEV_D(i)-E/dt; SoC_D=SoC_D+E/capD;                 end

        % ---------- 3a) V2G-Entladen im gleichen ΔP-Bereich --------------
        % (nur wenn SoC > 70 %  und solange Residuallast ≥ flexLowerBound bleibt)
        roomBelow  = max(deltaP - lower, 0);
        roomAbove  = max(upper - deltaP, 0);
        headroom2  = min(roomBelow, roomAbove);                % max. zul. Entladung
        if headroom2>0
            if availA&&SoC_A>v2gSOC&&headroom2>0
                P=min(maxA, headroom2);
                E=min(P*dt, (SoC_A-v2gSOC)*capA);
                pEV_A(i)=pEV_A(i)+E/dt; SoC_A=SoC_A-E/capA; headroom2=headroom2-P; end
            if availB&&SoC_B>v2gSOC&&headroom2>0
                P=min(maxB, headroom2);
                E=min(P*dt, (SoC_B-v2gSOC)*capB);
                pEV_B(i)=pEV_B(i)+E/dt; SoC_B=SoC_B-E/capB; headroom2=headroom2-P; end
            if availC&&SoC_C>v2gSOC&&headroom2>0
                P=min(maxC, headroom2);
                E=min(P*dt, (SoC_C-v2gSOC)*capC);
                pEV_C(i)=pEV_C(i)+E/dt; SoC_C=SoC_C-E/capC; headroom2=headroom2-P; end
            if availD&&SoC_D>v2gSOC&&headroom2>0
                P=min(maxD, headroom2);
                E=min(P*dt, (SoC_D-v2gSOC)*capD);
                pEV_D(i)=pEV_D(i)+E/dt; SoC_D=SoC_D-E/capD;             end
        end

    % ---------- 4) V2G-Entladen bei hoher Last --------------------------
    elseif deltaP>=upper
        headroom = max(deltaP - upper, 0);                   % >0
        if availA&&SoC_A>minSOC&&headroom>0
            P=min(maxA,headroom);
            E=min(P*dt,(SoC_A-minSOC)*capA);
            pEV_A(i)=pEV_A(i)+E/dt; SoC_A=SoC_A-E/capA; headroom=headroom-P; end
        if availB&&SoC_B>minSOC&&headroom>0
            P=min(maxB,headroom);
            E=min(P*dt,(SoC_B-minSOC)*capB);
            pEV_B(i)=pEV_B(i)+E/dt; SoC_B=SoC_B-E/capB; headroom=headroom-P; end
        if availC&&SoC_C>minSOC&&headroom>0
            P=min(maxC,headroom);
            E=min(P*dt,(SoC_C-minSOC)*capC);
            pEV_C(i)=pEV_C(i)+E/dt; SoC_C=SoC_C-E/capC; headroom=headroom-P; end
        if availD&&SoC_D>minSOC&&headroom>0
            P=min(maxD,headroom);
            E=min(P*dt,(SoC_D-minSOC)*capD);
            pEV_D(i)=pEV_D(i)+E/dt; SoC_D=SoC_D-E/capD;                end
    end

    % ---------- SoC-Vektoren aktualisieren ------------------------------
    SoC_A_vec(i)=SoC_A; SoC_B_vec(i)=SoC_B;
    SoC_C_vec(i)=SoC_C; SoC_D_vec(i)=SoC_D;
end

% ---------- Rückgabewerte ------------------------------------------------
pEV_total    = pEV_A + pEV_B + pEV_C + pEV_D;
SoCvec       = pA*SoC_A_vec + pB*SoC_B_vec + pC*SoC_C_vec + pD*SoC_D_vec;

pEV_groups.A = pEV_A;  pEV_groups.B = pEV_B;
pEV_groups.C = pEV_C;  pEV_groups.D = pEV_D;

SoC_groups.A = SoC_A_vec; SoC_groups.B = SoC_B_vec;
SoC_groups.C = SoC_C_vec; SoC_groups.D = SoC_D_vec;
end
