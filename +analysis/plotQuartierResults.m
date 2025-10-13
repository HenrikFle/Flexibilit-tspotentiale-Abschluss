function plotQuartierResults(normalDataSel,pvDataSel,residualResults,zeitraumName,currentWeek)
% -------------------------------------------------------------------------
% 1) Gesamtlast & PV  
% 2) Residuallast  
% 2b) Soll-Raumtemperatur (NEU)  
% 3) SoC-Gesamt  
% 4) SoC-Gruppen  
% 5) WP-Lastgang  
% 6) Flex-Energieblöcke
%
% Tages-Plots (Flex-Energieblöcke)
% ─ Batterie : Var-1 (fester Pmax) + Var-2 (fixes Δt)
% ─ EV       : Var-1 + Var-2
% ─ WP       : nur Var-2 (fixes Δt)  
%              • Abschalt-Block endet stets um 24 Uhr  
%              • Vorzeichen/Farben wie im Flex-Potential-Plot  
%                (blau = Netzaufnahme / rot = Netzentlastung)
% -------------------------------------------------------------------------

%% FIGUR 1 – Gesamtlast & PV-Einspeisung
figure('Name','Quartier-Gesamtübersicht', ...
       'NumberTitle','off','Position',[50 300 600 400]);
subplot(2,1,1); grid on; hold on;
plot(normalDataSel.Timestamp,normalDataSel.Power,'b-','LineWidth',1.5);
xlabel('Zeit','FontWeight','bold'); ylabel('Last [kW]','FontWeight','bold');
title([zeitraumName,' | KW ',num2str(currentWeek),' – Gesamtlast'],'FontWeight','bold');
datetick('x','dd-mmm HH:MM','keepticks','keeplimits');
legend('Gesamtlast','Location','best'); hold off;

subplot(2,1,2); grid on; hold on;
plot(pvDataSel.Timestamp,pvDataSel.Power,'r-','LineWidth',1.5);
xlabel('Zeit','FontWeight','bold'); ylabel('PV [kW]','FontWeight','bold');
title([zeitraumName,' | KW ',num2str(currentWeek),' – PV-Einspeisung'],'FontWeight','bold');
datetick('x','dd-mmm HH:MM','keepticks','keeplimits');
legend('PV-Einspeisung','Location','best'); hold off;

%% FIGUR 2 – Residuallast (verschiedene Szenarien)
figR = figure('Name','Residuallast','NumberTitle','off','Position',[700 50 800 350]);
ax2 = axes('Parent',figR); hold(ax2,'on'); grid(ax2,'on');

X  = residualResults.Timestamp;
Y0 = residualResults.Residual_NoStorage;
Y1 = residualResults.Residual_WithBatt;
Y2 = Y0 + (residualResults.wpFlexAgg_kW - residualResults.wpAgg_kW);
Y3 = Y0 - residualResults.pEV_flex;
hasFlexBounds = isfield(residualResults,'flexLowerBound_kW') && ...
                isfield(residualResults,'flexUpperBound_kW');
if hasFlexBounds
    flexLower = residualResults.flexLowerBound_kW(:);
    flexUpper = residualResults.flexUpperBound_kW(:);
else
    flexLower = [];
    flexUpper = [];
end

hBase     = plot(ax2,X,Y0, 'k-','LineWidth',2,'DisplayName','Residuallast');
hBattLine = plot(ax2,X,Y1, 'm-','LineWidth',2,'DisplayName','Mit Batterie','Visible','off');
hBattFill = fill(ax2, [X;flipud(X)], [Y0;flipud(Y1)], [0 0 0.6], ...
    'FaceAlpha',0.2,'EdgeColor','none','DisplayName','Batterie','Visible','off');
hFlexLower = matlab.graphics.chart.primitive.Line.empty;
hFlexUpper = matlab.graphics.chart.primitive.Line.empty;
if hasFlexBounds
    hFlexLower = plot(ax2,X,flexLower,'Color',[0.85 0.33 0.10], ...
        'LineStyle',':','LineWidth',1.5,'DisplayName','Flex-Untergrenze');
    hFlexUpper = plot(ax2,X,flexUpper,'Color',[0.93 0.69 0.13], ...
        'LineStyle',':','LineWidth',1.5,'DisplayName','Flex-Obergrenze');
end
hWP       = plot(ax2,X,Y2, 'g--','LineWidth',2,'DisplayName','Mit flexibler WP','Visible','off');
hEV       = plot(ax2,X,Y3, 'c-.','LineWidth',2,'DisplayName','Mit flexiblem EV','Visible','off');

yline(ax2,0,'k--','HandleVisibility','off');
xlabel(ax2,'Zeit','FontWeight','bold'); ylabel(ax2,'Leistung [kW]','FontWeight','bold');
title(ax2,[zeitraumName,' | KW ',num2str(currentWeek),' – Residuallast'],'FontWeight','bold');
datetick(ax2,'x','dd-mmm HH:MM','keepticks','keeplimits');
legend(ax2,'Location','best');

% Checkboxen für Flex-Potenziale
uicontrol('Parent',figR,'Style','checkbox','String','Batterie','Value',0, ...
    'Units','normalized','Position',[0.82,0.75,0.15,0.05], ...
    'Callback',@(src,~) toggleVisible([hBattLine,hBattFill], src.Value));
uicontrol('Parent',figR,'Style','checkbox','String','WP','Value',0, ...
    'Units','normalized','Position',[0.82,0.65,0.15,0.05], ...
    'Callback',@(src,~) toggleVisible(hWP, src.Value));
uicontrol('Parent',figR,'Style','checkbox','String','EV','Value',0, ...
    'Units','normalized','Position',[0.82,0.55,0.15,0.05], ...
    'Callback',@(src,~) toggleVisible(hEV, src.Value));

%% FIGUR 2b – Soll-Raumtemperatur (NEU)
if isfield(residualResults,'Tset_Heat')
    figure('Name','Soll-Raumtemperatur','NumberTitle','off','Position',[700 420 800 250]);
    grid on; hold on;
    plot(residualResults.Timestamp, residualResults.Tset_Heat, ...
         'Color',[0.85 0.33 0.10],'LineWidth',1.5);
    datetick('x','dd-mmm HH:MM','keepticks','keeplimits');
    xlabel('Zeit','FontWeight','bold'); ylabel('T_{set} [°C]','FontWeight','bold');
    title([zeitraumName,' | KW ',num2str(currentWeek),' – Soll-Raumtemperatur'],'FontWeight','bold');
    ylim([min(residualResults.Tset_Heat)-1, max(residualResults.Tset_Heat)+1]);
end

%% FIGUR 3 – Raumtemperaturen (statisch und dynamisch WP)
figure('Name','Raumtemperaturen Wochenverlauf','NumberTitle','off','Position',[700 300 600 400]);
hold on; grid on;
plot(residualResults.Timestamp, residualResults.T_room_stat, 'b-','LineWidth',1.5,'DisplayName','T statische WP');
plot(residualResults.Timestamp, residualResults.T_room_dyn,  'r-','LineWidth',1.5,'DisplayName','T dynamische WP');
xlabel('Zeit','FontWeight','bold'); ylabel('Raumtemperatur [°C]','FontWeight','bold');
title([zeitraumName,' | KW ',num2str(currentWeek),' – Raumtemperaturen'],'FontWeight','bold');
datetick('x','dd-mmm HH:MM','keeplimits','keepticks');
legend('Location','best');

%% FIGUR 2a – Tages-Profile der Flex-Blöcke
yr = year(X(1));
switch zeitraumName
    case 'Winter',        t0 = datetime(yr,1,8);
    case 'Sommer',        t0 = datetime(yr,8,5);   %%6,28
    case 'Übergangszeit', t0 = datetime(yr,9,6);
    otherwise,            return;
end
idDay = (X>=t0) & (X<t0+days(1));
if ~any(idDay), return; end

dt_h   = residualResults.dtHours;
colChg = [0.05 0.10 0.55];            % Blau  – Netzaufnahme / Laden
colDis = [0.65 0.05 0.05];            % Rot   – Netzentlastung / Entladen
alpha  = 0.35;

% --- Batterie – Tagesprofil (Var-1 + Var-2) ---
figure('Name',[zeitraumName,' – Tagesprofil Batterie'], ...
       'NumberTitle','off','Position',[700 420 900 320]);
axB = gca; hold(axB,'on'); grid(axB,'on');
plot(axB,X(idDay),Y0(idDay),'k-','LineWidth',1.4,'DisplayName','Residuallast');
yline(axB,0,'k--','HandleVisibility','off');
xlabel(axB,'Zeit','FontWeight','bold'); ylabel(axB,'Leistung [kW]','FontWeight','bold');
title(axB,[zeitraumName,' (',datestr(t0,'dd-mmm'),') – Batterie'],'FontWeight','bold');
datetick(axB,'x','HH:MM','keepticks','keeplimits');

PmaxB  = max(residualResults.pMaxBatt_kW,eps);
pB_day = residualResults.pBatt_kW(idDay);
EdisB  = sum(max(0,pB_day))*dt_h;
EchgB  = -sum(min(0,pB_day))*dt_h;

% Var-1: Pmax-Block
if EdisB>0
    tmp=X(idDay); [~,iMax]=max(Y0(idDay)); tMax=tmp(iMax);
    half=hours((EdisB/PmaxB)/2);
    patch(axB,[tMax-half tMax+half tMax+half tMax-half],[0 0 -PmaxB -PmaxB], ...
          colDis,'FaceAlpha',alpha,'EdgeColor','none', ...
          'DisplayName',sprintf('Batterie entladen (−%.1f kWh)',EdisB));
end
if EchgB>0
    tmp=X(idDay); [~,iMin]=min(Y0(idDay)); tMin=tmp(iMin);
    half=hours((EchgB/PmaxB)/2);
    patch(axB,[tMin-half tMin+half tMin+half tMin-half],[0 0 PmaxB PmaxB], ...
          colChg,'FaceAlpha',alpha,'EdgeColor','none', ...
          'DisplayName',sprintf('Batterie laden (+%.1f kWh)',EchgB));
end

% Var-2: Fixed-Δt-Block
negB = find(Y0(idDay)<0);
if ~isempty(negB) && EdisB>0 && EchgB>0
    tmp2 = X(idDay);
    tL0 = tmp2(negB(1));
    tL1 = tmp2(negB(end)) + minutes(dt_h*60);
    PchgB = EchgB / hours(tL1 - tL0);
    patch(axB,[tL0 tL1 tL1 tL0],[0 0 PchgB PchgB],...
          colChg,'FaceAlpha',alpha,'EdgeColor','none','HandleVisibility','off');
    tD0 = tL1;
    tD1 = t0 + days(1);
    PdisB = -EdisB / hours(tD1 - tD0);
    patch(axB,[tD0 tD1 tD1 tD0],[0 0 PdisB PdisB],...
          colDis,'FaceAlpha',alpha,'EdgeColor','none','HandleVisibility','off');
end
legend(axB,'Location','best');

% --- EV – Tagesprofil (Var-1 + Var-2) ---
figure('Name',[zeitraumName,' – Tagesprofil EV'], ...
       'NumberTitle','off','Position',[700 720 900 320]);
axE = gca; hold(axE,'on'); grid(axE,'on');
plot(axE,X(idDay),Y0(idDay),'k-','LineWidth',1.4,'DisplayName','Residuallast');
yline(axE,0,'k--','HandleVisibility','off');
xlabel(axE,'Zeit','FontWeight','bold'); ylabel(axE,'Leistung [kW]','FontWeight','bold');
title(axE,[zeitraumName,' (',datestr(t0,'dd-mmm'),') – EV'],'FontWeight','bold');
datetick(axE,'x','HH:MM','keepticks','keeplimits');

pEV   = residualResults.pEV_flex(idDay);
EdisE = sum(max(0,pEV))*dt_h;
EchgE = -sum(min(0,pEV))*dt_h;

% Var-1: Pmax-Block
if EdisE>0
    tmp=X(idDay); [~,iMax]=max(Y0(idDay)); tMax=tmp(iMax);
    avail=models.aggregatedEVChargingAvailability(hour(tMax)+minute(tMax)/60);
    PmaxE=avail*residualResults.pMaxEV_kW;
    half=hours((EdisE/PmaxE)/2);
    patch(axE,[tMax-half tMax+half tMax+half tMax-half],[0 0 -PmaxE -PmaxE], ...
          colDis,'FaceAlpha',alpha,'EdgeColor','none', ...
          'DisplayName',sprintf('EV entladen (−%.1f kWh)',EdisE));
end
if EchgE>0
    tmp=X(idDay); [~,iMin]=min(Y0(idDay)); tMin=tmp(iMin);
    avail=models.aggregatedEVChargingAvailability(hour(tMin)+minute(tMin)/60);
    PmaxE=avail*residualResults.pMaxEV_kW;
    half=hours((EchgE/PmaxE)/2);
    patch(axE,[tMin-half tMin+half tMin+half tMin-half],[0 0 PmaxE PmaxE], ...
          colChg,'FaceAlpha',alpha,'EdgeColor','none', ...
          'DisplayName',sprintf('EV laden (+%.1f kWh)',EchgE));
end

% Var-2: Fixed-Δt-Block
negE = find(Y0(idDay)<0);
if ~isempty(negE) && EdisE>0 && EchgE>0
    tmp3 = X(idDay);
    tL0 = tmp3(negE(1));
    tL1 = tmp3(negE(end)) + minutes(dt_h*60);
    PchgE = EchgE / hours(tL1 - tL0);
    patch(axE,[tL0 tL1 tL1 tL0],[0 0 PchgE PchgE],...
          colChg,'FaceAlpha',alpha,'EdgeColor','none','HandleVisibility','off');
    tD0 = tL1;
    tD1 = t0 + days(1);
    PdisE = -EdisE / hours(tD1 - tD0);
    patch(axE,[tD0 tD1 tD1 tD0],[0 0 PdisE PdisE],...
          colDis,'FaceAlpha',alpha,'EdgeColor','none','HandleVisibility','off');
end
legend(axE,'Location','best');

%% --- Wärmepumpen (Heizung + DHW) – Tagesprofil (Var-2) ---
figure('Name',[zeitraumName,' – Tagesprofil Wärmepumpe gesamt'], ...
       'NumberTitle','off','Units','normalized','Position',[0.1 0.25 0.8 0.35]);
axW = gca; hold(axW,'on'); grid(axW,'on');
plot(axW,X(idDay),Y0(idDay),'k-','LineWidth',1.4,'DisplayName','Residuallast');
yline(axW,0,'k--','HandleVisibility','off');
xlabel(axW,'Zeit','FontWeight','bold'); ylabel(axW,'Leistung [kW]','FontWeight','bold');
title(axW,[zeitraumName,' (',datestr(t0,'dd-mmm'),') – Wärmepumpe gesamt'],'FontWeight','bold');
datetick(axW,'x','HH:MM','keepticks','keeplimits');

% Differenz flexibel – statisch (Heizung + DHW)
dWP_total = (residualResults.wpFlexAgg_kW + residualResults.dhwFlexAgg_kW) - ...
            (residualResults.wpAgg_kW + residualResults.dhwAgg_kW);
wpDay = dWP_total(idDay);

% Energiebilanz (kWh) – positive / negative Teile
E_pos =  sum(max(0,wpDay)) * dt_h;   % Mehrverbrauch (Netzaufnahme)
E_neg = -sum(min(0,wpDay)) * dt_h;   % Einsparung  (Netzentlastung)

negW = find(Y0(idDay)<0);
if ~isempty(negW) && E_pos>0 && E_neg>0
    tmp = X(idDay);
    tPos0 = tmp(negW(1));                 % während PV-Überschuss -> Netzaufnahme
    tPos1 = tmp(negW(end)) + minutes(dt_h*60);
    P_pos =  E_pos / hours(tPos1 - tPos0);
    patch(axW,[tPos0 tPos1 tPos1 tPos0],[0 0 P_pos P_pos], ...
          colChg,'FaceAlpha',alpha,'EdgeColor','none', ...
          'DisplayName',sprintf('Mehrverbrauch (+%.1f kWh)',E_pos));

    tNeg0 = tPos1;                        % anschließend bis 24 Uhr -> Netzentlastung
    tNeg1 = t0 + days(1);
    P_neg = -E_neg / hours(tNeg1 - tNeg0);
    patch(axW,[tNeg0 tNeg1 tNeg1 tNeg0],[0 0 P_neg P_neg], ...
          colDis,'FaceAlpha',alpha,'EdgeColor','none', ...
          'DisplayName',sprintf('Einsparung (−%.1f kWh)',E_neg));
end
legend(axW,'Location','best');



%% FIGUR 3 – SoC-Verlauf
figure('Name','SoC-Verlauf','NumberTitle','off','Position',[700 450 800 300]);
ax3 = axes('Parent',gcf); hold(ax3,'on'); grid(ax3,'on');
if isfield(residualResults,'SoC_EV')
    plot(ax3,X,residualResults.SoC_EV,'Color',[0 .8 0],'LineWidth',1.5,'DisplayName','EV-SoC');
end
if isfield(residualResults,'SoC_Batt')
    plot(ax3,X,residualResults.SoC_Batt,'Color',[1 0 1],'LineWidth',1.5,'DisplayName','Batt-SoC');
end
datetick(ax3,'x','dd-mmm HH:MM','keepticks','keeplimits');
xlabel(ax3,'Zeit','FontWeight','bold'); ylabel(ax3,'SoC [–]','FontWeight','bold');
title(ax3,'Aggregierter SoC-Verlauf','FontWeight','bold');
legend(ax3,'Location','best');

%% FIGUR 4 – Gruppenspezifische EV-SoC
if isfield(residualResults,'SoC_groups')
    figure('Name','Gruppenspezifische EV-SoC','NumberTitle','off','Position',[100 100 800 600]);
    t = residualResults.Timestamp;
    plot(t,residualResults.SoC_groups.A,'b-','LineWidth',1.5); hold on;
    plot(t,residualResults.SoC_groups.B,'r-','LineWidth',1.5);
    plot(t,residualResults.SoC_groups.C,'g-','LineWidth',1.5);
    plot(t,residualResults.SoC_groups.D,'k-','LineWidth',1.5);
    xlabel('Zeit','FontWeight','bold'); ylabel('SoC','FontWeight','bold'); grid on; 
    title('EV-SoC der Gruppen','FontWeight','bold');
    legend('A','B','C','D','Location','best');
end

%% FIGUR 5 – WP-Lastgang (aggregiert)
figure('Name','Wärmepumpen-Lastgang','NumberTitle','off','Position',[50 50 600 400]);
grid on; hold on;
plot(X,residualResults.wpAgg_kW,'b-','LineWidth',1.5,'DisplayName','WP statisch');
plot(X,residualResults.wpFlexAgg_kW,'r--','LineWidth',1.5,'DisplayName','WP flexibel');
xlabel('Zeit','FontWeight','bold'); ylabel('Leistung [kW]','FontWeight','bold'); 
title([zeitraumName,' | KW ',num2str(currentWeek),' – WP-Lastgang'],'FontWeight','bold');
datetick('x','dd-mmm HH:MM','keepticks','keeplimits');
legend('Location','best');

%% FIGUR 5a – WP-DHW Lastgang (aggregiert)
figure('Name','DHW-WP-Lastgang','NumberTitle','off','Position',[680 50 600 400]);
grid on; hold on;
plot(X,residualResults.dhwAgg_kW,'b-','LineWidth',1.5,'DisplayName','DHW statisch');
plot(X,residualResults.dhwFlexAgg_kW,'r--','LineWidth',1.5,'DisplayName','DHW flexibel');
xlabel('Zeit','FontWeight','bold'); ylabel('Leistung [kW]','FontWeight','bold');
title([zeitraumName,' | KW ',num2str(currentWeek),' – WP-DHW'],'FontWeight','bold');
datetick('x','dd-mmm HH:MM','keepticks','keeplimits');
legend('Location','best');

%% FIGUR 6 – Flex-Energieblöcke (Wochen-Mittel)
ft = residualResults.flexEnergyTable;

% --- 1) Vorzeichen/Kategorien aufbereiten --------------------------------
posPlot =  ft.Epos_kWh;      % Mehrverbrauch / Laden
negPlot =  ft.Eneg_kWh;      % Einsparung   / Entladen

% Für Batterie & EV: Laden positiv, Entladen negativ
swapIdx = ismember(ft.names, {'Batterie','EV'});
posPlot(swapIdx) = -ft.Eneg_kWh(swapIdx);   % Laden  (+)
negPlot(swapIdx) = -ft.Epos_kWh(swapIdx);   % Entladen (−)

% --- 1b) keine Kategorien entfernen ------------------------------------
namesPlot = ft.names;
posPlotF  = posPlot;
negPlotF  = negPlot;

% --- 2) Balkenplot -------------------------------------------------------
figure('Name','Flex-Energieblöcke','NumberTitle','off','Position',[900 50 500 350]);
hb = barh(categorical(namesPlot), [negPlotF, posPlotF], 'stacked');
xlabel('Ø [kWh/Tag]','FontWeight','bold'); title('Flexibilitätspotenziale','FontWeight','bold');
set(gca,'FontWeight','bold'); grid on;

% Farben & Transparenz: Rot = Netzentlastung, Blau = Netzaufnahme
hb(1).FaceColor = colDis;
hb(2).FaceColor = colChg;
hb(1).FaceAlpha = alpha;
hb(2).FaceAlpha = alpha;

legend({'Netzentlastung','Netzbezug'}, 'Location','best');

% --- 3) Beschriftungen ---------------------------------------------------
Ycats = categorical(namesPlot); yIdx = double(Ycats);
for k = 1:numel(namesPlot)
    y = yIdx(k);
    if posPlotF(k) ~= 0
        text(posPlotF(k)/2, y, sprintf('%+.1f kWh', posPlotF(k)), ...
             'HorizontalAlignment','center','VerticalAlignment','middle', ...
             'Color','k','FontWeight','bold');
    end
    if negPlotF(k) ~= 0
        text(negPlotF(k)/2, y, sprintf('%+.1f kWh', negPlotF(k)), ...
             'HorizontalAlignment','center','VerticalAlignment','middle', ...
             'Color','k','FontWeight','bold');
    end
end

fprintf('\nØ flexible Energie pro Tag [kWh]\n---------------------------------\n');
EposF = ft.Epos_kWh;
EnegF = ft.Eneg_kWh;
for k = 1:numel(namesPlot)
    fprintf('%-10s : %+8.1f (pos)   %+8.1f (neg)\n', ...
            namesPlot{k}, EposF(k), EnegF(k));
end
fprintf('---------------------------------\n\n');





   %% --- Durchschnittliche tägliche Energie der Wärmepumpe gesamt in der aktuellen Woche ---
% X und residualResults.* sind bereits definiert
% residualResults.dtHours enthält den Zeitschritt in Stunden (z.B. 0.25)

% 1) Indizes für die aktuelle Kalenderwoche ermitteln
idxWeek = week(X) == currentWeek;

% 2) Gesamtenergie der statischen WP (Heizung + DHW) in dieser Woche (kWh)
wpTotal = residualResults.wpAgg_kW + residualResults.dhwAgg_kW;
E_WP_week = sum(wpTotal(idxWeek)) * residualResults.dtHours;

% 3) Durchschnittliche Energie pro Tag (kWh/Tag)
avgDaily_WP = E_WP_week / 7;

% 4) Ausgabe in der Konsole
fprintf('Ø tägliche Energie Wärmepumpe gesamt KW %d: %.2f kWh/Tag\n', ...
        currentWeek, avgDaily_WP);







end

% --------------------- Lokale Hilfsfunktion -------------------------------
function toggleVisible(h, state)
    if state
        set(h, 'Visible', 'on');
    else
        set(h, 'Visible', 'off');
    end



end
