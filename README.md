#### Step 1: Data Acquisition and Preprocessing
- The code starts by clearing the MATLAB workspace to ensure a clean environment.
- metoData: Contains hourly ambient temperature data for a year.
- HouseArea, WindowsSArea, WallArea, WallThickness, k: Define building parameters affecting heat transfer.
- T_internal: Desired indoor temperature for thermal comfort.
- SHGC: Solar Heat Gain Coefficient of the windows.
- Heat: Contains hourly temperature data for a different dataset (may not be used depending on the code's logic).

```matlab
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
```

#### Step 2: Heat Transfer Calculations:
- Conduction: The code calculates the heat gain (or loss) through conduction through walls based on the temperature difference between inside and outside, wall area, thickness, and thermal conductivity (k).
- Solar Gain: The solar heat gain through windows is calculated considering the window area, solar heat gain coefficient (SHGC), and hourly global irradiance data from metoData.

```matlab
Q_cond = k*WallArea*(metoData.T_amb - T_internal)/WallThickness; %[W]
Q_solar = WindowsSArea*SHGC*metoData.G_i__W_m2_; %[W]
HeatTransfer.Q_net = Q_solar + Q_cond;

Q_demand_before = min(Q_solar + Q_cond, 0);
HeatTransfer.Q_Demand = Q_demand_before; %[W]
```

#### Step 3: PCM Modeling
- Two PCMs (Phase Change Materials) with different melting points are defined using their specific properties (specific heat, melting temperature, latent heat).
- For each hour:
	- The difference between ambient temperature and the melting point of each PCM is calculated.
	- Based on this difference, the code determines if the PCM stores or releases heat.
	- The amount of heat stored/released is calculated using the appropriate specific heat or latent heat value, considering the time step and the area/mass of the PCM.

```matlab
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
```

#### Step 4: Demand Reduction & Heat Pump
- Demand Before PCMs: The total heat demand before PCM integration is calculated by summing the conduction heat loss, solar heat gain, and any internal heat sources (potentially from Heat).
- Demand After PCMs: The heat stored/released by the PCMs is subtracted from the original demand, resulting in the adjusted heat demand after PCM integration.
- Heat Pump Power: Assuming a heat pump is used to meet the remaining heating demand, the code estimates its power consumption by dividing the demand by the heat pump's Coefficient of Performance (COP).

```matlab
% Heat Demand
Q_PCM_release_Sum = Q_PCM_release_W + Q_PCM_release_S;
Q_demand_after = Q_demand_before - Q_PCM_release_Sum; %[W]

Total_Q_PCM = abs(sum(Q_PCM_release_Sum))/10^6;
Total_Q_demand_before = abs(sum(Q_demand_before))/10^6; %[MW]
Total_Q_demand_after = abs(sum(Q_demand_after))/10^6;

Q_perc_Reduction = abs(Total_Q_demand_after - Total_Q_demand_before)/Total_Q_demand_before*100;

HeatTransfer.Q_demand_after = Q_demand_after;

% Heat Pump
COP = 5; %COP=Q/P
P_before = abs(Total_Q_demand_before)/COP;
P_after = abs(Total_Q_demand_after)/COP;
Total_P_before = sum(P_before);
Total_P_after = sum(P_after);
```

#### Step 5: Economic Analysis
- Monthly Electricity Consumption: The total heat pump power consumption is calculated and converted to monthly electricity consumption (MWh).
- Electricity Cost: This is calculated by multiplying the monthly electricity consumption by the corresponding monthly electricity price from E_price.
- Cost Savings: The difference in electricity costs between the scenarios with and without PCMs is calculated for each month, representing the potential cost savings.
- Payback Period: The total investment cost for the PCM system is divided by the annual cost savings to estimate the payback period.

```matlab
% Economicial aspect
E_price = readtable("ML_E_price.csv"); % [PLN/MWh]

Q_demand_before_m = splitapply(@sum, HeatTransfer.Q_Demand, HeatTransfer.m); %[W]
Q_demand_after_m = splitapply(@sum, HeatTransfer.Q_demand_after, HeatTransfer.m); 
P_after_m = abs(Q_demand_after_m)/COP/10^6; %[MWh]
P_before_m = abs(Q_demand_before_m)/COP/10^6;

ElecPaid_before_m = E_price.P.*P_before_m;
ElecPaid_after_m = E_price.P.*P_after_m;
ElecPaid_Reduction_m = abs(ElecPaid_after_m - ElecPaid_before_m);
ElecPaid_Reduction_y = sum(ElecPaid_Reduction_m);
```

#### Step 6: Visualization
- Daily & Monthly Heat Demand: Plots are generated to visualize the daily and monthly heating demand before and after PCM integration. (Step 4)
- Electrical Expense: A plot illustrates the monthly electricity expenses with and without PCMs, highlighting the potential cost savings. (Step 5)

```matlab
%Heat Demand
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

%Electrical Expense
plot(ElecPaid_before_m, 'DisplayName', 'E expense before');
hold on
plot(ElecPaid_after_m, 'DisplayName', 'E expense after');
extended_xlimE = [1, 12];
xlim(extended_xlimE);
extended_ylimE = [0, 2200];
ylim(extended_ylimE);
legend('show');
title('Monthly electrical expense (PLN)');
```

#### Conclusion:
- This code simulates the impact of PCMs on building heating demand and potential cost savings in electricity bills.
- Several assumptions about building parameters, weather data, and heat pump performance are made.
- The economic analysis provides a preliminary estimate and may require further refinement based on specific costs and financial considerations.
