classdef PCM
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        MeltingTemp
        Diameter
        Density
        NumberPCM
        LatentCoeff
        Volume_mm
        Volume_l
        Mass
        MassTotal
        Q_Latent
    end
    
    methods
        function obj = PCM(MeltingTemp, Diameter, Density, NumberPCM, LatentCoeff)
            %UNTITLED Construct an instance of this class
            %   Detailed explanation goes here
            obj.MeltingTemp = MeltingTemp;
            obj.Diameter = Diameter; % [mm]
            obj.Density = Density;
            obj.NumberPCM = NumberPCM;
            obj.LatentCoeff = LatentCoeff;
            obj.Volume_mm = (4/3)*pi()*(obj.Diameter/2)^3; %mm
            obj.Volume_l = obj.Volume_mm/(10^6); %l
            obj.Mass = obj.Volume_l*obj.Density;         
            obj.MassTotal = obj.Mass*obj.NumberPCM;
            obj.Q_Latent = obj.MassTotal*obj.LatentCoeff;
        end
    end
end

