clear;

metoData = readtable("ML_meto_s90_pl_y.csv");
Temp = metoData(:,["m" "d" "h" "T_amb"]);

HouseArea = 100;
WindowsSArea = 24;
WallArea = 96;
WallThickness = 0.1;

k = 0.94; %Select SLWAC Argex concrete
T_internal = 22; %Thermal Comfort Temperature
SHGC = 0.86; %Ingle-pane clear glass

Heat = readtable("ML_Heat_y.csv");
HeatTransfer = Heat(:,["m", "d", "h"]);
HeatTransfer.T = Temp.T_amb;

Q_cond = k*WallArea*(metoData.T_amb - T_internal)/WallThickness; %[W]
Q_solar = WindowsSArea*SHGC*metoData.G_i__W_m2_; %[W]
HeatTransfer.Q_net = Q_solar + Q_cond;

Q_demand_before = min(Q_solar + Q_cond, 0);
HeatTransfer.Q_Demand = Q_demand_before; %[W]

%PCM 
PlateArea = 1; %[m2]
ConvCoeff = 1.95; %[W/m2K]

%High Melting Point PCM
PCM1 = PCM(18.1, 100, 0.77, 100, 236);

Q_PCM_store_S = zeros(height(Temp), 1);
Q_PCM_release_S = zeros(height(Temp), 1);
Q_conv = zeros(height(Temp), 1);

for hour = 2:height(Temp)

    Q_conv(hour) = ConvCoeff*PlateArea*(Temp.T_amb(hour)-PCM1.MeltingTemp)*3600; %[J/h]
    Q_PCM_store_S(hour) = Q_PCM_store_S(hour-1) + Q_conv(hour);
    if Q_PCM_store_S(hour) < 0
        Q_PCM_store_S(hour) = 0;
    elseif Q_PCM_store_S(hour) >= PCM1.Q_Latent
        Q_PCM_store_S(hour) = PCM1.Q_Latent;
    end

    for hour = 2:height(Temp)
        if Q_PCM_store_S(hour) < Q_PCM_store_S(hour-1)
            Q_PCM_release_S(hour) = Q_PCM_release_S(hour)+Q_conv(hour);
            if abs(Q_PCM_release_S(hour)) >= Q_PCM_store_S(hour-1)
                Q_PCM_release_S(hour) = -(Q_PCM_store_S(hour-1));
            end
        else
            Q_PCM_release_S(hour) = 0;
        end
    end
end

HeatTransfer.Q_PCM_store_S = Q_PCM_store_S;
HeatTransfer.Q_PCM_release_S = Q_PCM_release_S;

%Low Melting Point PCM
PCM2 = PCM(5.9, 100, 0.77, 100, 258);

Q_PCM_store_W = zeros(height(Temp), 1);
Q_PCM_release_W = zeros(height(Temp), 1);
Q_conv = zeros(height(Temp), 1);

for hour = 2:height(Temp)

    Q_conv(hour) = ConvCoeff*PlateArea*(Temp.T_amb(hour)-PCM2.MeltingTemp)*3600; %[J/h]
    Q_PCM_store_W(hour) = Q_PCM_store_W(hour-1) + Q_conv(hour);
    if Q_PCM_store_W(hour) < 0
        Q_PCM_store_W(hour) = 0;
    elseif Q_PCM_store_W(hour) >= PCM2.Q_Latent
        Q_PCM_store_W(hour) = PCM2.Q_Latent;
    end

    for hour = 2:height(Temp)
        if Q_PCM_store_W(hour) < Q_PCM_store_W(hour-1)
            Q_PCM_release_W(hour) = Q_PCM_release_W(hour)+Q_conv(hour);
            if abs(Q_PCM_release_W(hour)) >= Q_PCM_store_W(hour-1)
                Q_PCM_release_W(hour) = -(Q_PCM_store_W(hour-1));
            end
        else
            Q_PCM_release_W(hour) = 0;
        end
    end
end

HeatTransfer.Q_PCM_store_W = Q_PCM_store_W;
HeatTransfer.Q_PCM_release_W = Q_PCM_release_W;

Q_PCM_release_Sum = Q_PCM_release_W + Q_PCM_release_S;
Q_demand_after = Q_demand_before - Q_PCM_release_Sum; %[W]

Total_Q_PCM = abs(sum(Q_PCM_release_Sum))/10^6;
Total_Q_demand_before = abs(sum(Q_demand_before))/10^6; %[MW]
Total_Q_demand_after = abs(sum(Q_demand_after))/10^6;

Q_perc_Reduction = abs(Total_Q_demand_after - Total_Q_demand_before)/Total_Q_demand_before*100;

HeatTransfer.Q_demand_after = Q_demand_after;

Summary_Q = table();
Summary_Q.Total_Q_demand_before = Total_Q_demand_before;
Summary_Q.Total_Q_demand_after = Total_Q_demand_after;

Q_demand_before_matrix = reshape(Q_demand_before, 24, []);
Total_Q_demand_before_matrix = sum(Q_demand_before_matrix);
Q_demand_before_days = 1:length(Total_Q_demand_before_matrix);

Q_demand_after_matrix = reshape(Q_demand_after, 24, []);
Total_Q_demand_after_matrix = sum(Q_demand_after_matrix);
Q_demand_after_days = 1:length(Total_Q_demand_after_matrix);

plot(Q_demand_before_days, -(Total_Q_demand_before_matrix), 'DisplayName', 'Q demand before');
hold on
plot(Q_demand_after_days, -(Total_Q_demand_after_matrix), 'DisplayName', 'Q demand after');
title('Total daily Q demand before and after Over a Year');
xlabel('Day');
ylabel('Daily Q demand (W)');
grid on;
xlim([1, 366]);
legend('show');

figure
bar(Summary_Q{1,:})
extended_ylimQ = [0, 85];  
ylim(extended_ylimQ);
ylabel("Heat Analysis (MW)")
xticklabels(Summary_Q.Properties.VariableNames)
title('Summary of Heat Demand (MW)');

%% Heat Pump

COP = 5; %COP=Q/P
P_before = abs(Total_Q_demand_before)/COP;
P_after = abs(Total_Q_demand_after)/COP;
Total_P_before = sum(P_before);
Total_P_after = sum(P_after);

Summary_P = table();
Summary_P.P_before = Total_P_before;
Summary_P.P_after = Total_P_after;

figure
bar(Summary_P{1,:})
ylabel("Power Analysis (MWh)")
xticklabels(Summary_P.Properties.VariableNames)
extended_ylimP = [0, 17];
ylim(extended_ylimP);
title('Summary of Power consumption (MWh)');

%% Economicial aspect

E_price = readtable("ML_E_price.csv"); % [PLN/MWh]

Q_demand_before_m = splitapply(@sum, HeatTransfer.Q_Demand, HeatTransfer.m); %[W]
Q_demand_after_m = splitapply(@sum, HeatTransfer.Q_demand_after, HeatTransfer.m); 
P_after_m = abs(Q_demand_after_m)/COP/10^6; %[MWh]
P_before_m = abs(Q_demand_before_m)/COP/10^6;

ElecPaid_before_m = E_price.P.*P_before_m;
ElecPaid_after_m = E_price.P.*P_after_m;
ElecPaid_Reduction_m = abs(ElecPaid_after_m - ElecPaid_before_m);
ElecPaid_Reduction_y = sum(ElecPaid_Reduction_m);

plot(ElecPaid_before_m, 'DisplayName', 'E expense before');
hold on
plot(ElecPaid_after_m, 'DisplayName', 'E expense after');
extended_xlimE = [1, 12];
xlim(extended_xlimE);
extended_ylimE = [0, 2200];
ylim(extended_ylimE);
legend('show');
title('Monthly electrical expense (PLN)');

Total_Investment = 2637.51;
PayBackPeriod = ceil(Total_Investment/ElecPaid_Reduction_y);