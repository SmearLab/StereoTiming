function Blink
global BpodSystem

%% Setup (runs once before the first trial)
MaxTrials = 1000; % Set to some sane value, for preallocation

%--- Define parameters and trial structure
S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
if isempty(fieldnames(S))  % If chosen settings file was an empty struct, populate struct with default settings
 
    S.GUI.OdorDeliveryTime = 5;
    S.GUI.LickWindow = 5;
    S.GUI.RewardAmount = 5;
    %(make sure to specify .GUI, otherwise it'll throw an unexpected field error)
    
    
    %Sniff paramters structure 
    S.GUI.SniffLatency = 5; 
    S.GUI.Pressure1WIP = 0; %<Not wired up!!!>
    S.GUI.Pressure2WIP = -1; %<Not wired up!!!>
    S.GUIPanels.SniffDefinitionsWIP = {'Pressure1WIP', 'Pressure2WIP', 'SniffLatency'};
end
    
    % Define default settings here as fields of S (i.e S.InitialDelay = 3.2)
    % Note: Any parameters in S.GUI will be shown in UI edit boxes. 
    % See ParameterGUI plugin documentation to show parameters as other UI types (listboxes, checkboxes, buttons, text)

%--- Initialize plots and start USB connections to any modules
BpodParameterGUI('init', S); % Initialize parameter GUI plugin
if isempty(fieldnames(S))  
 
end

%% Main loop (runs once per trial)
for currentTrial = 1:MaxTrials
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    
    %--- Typically, a block of code here will compute variables for assembling this trial's state machine
    r = rand();
    if r <= 0.5
        ValveToOpen = 88;
    else
        ValveToOpen = 56;  
    end
    
    %--- Assemble state machine
    sma = NewStateMachine();

    sma = AddState(sma, 'Name', 'Sniff1', ...               %Adds a new state called "Sniff1" to the matrix. 
        'Timer', 1,...                                                         %Sets the internal timer of "On state" to 0ish seconds. 
        'StateChangeConditions', {'Port2In', 'Sniff2'},...  %When the analog input device detects no pressure, it sends a digital input to port 2, transitioning to Sniff2
        'OutputActions', {});                           %No output action

    sma = AddState(sma, 'Name', 'Sniff2', ...    %Adds a new state called "Sniff2" to the matrix.             
        'Timer', S.GUI.SniffLatency,...  %Sets the timer on this state to take input for response time from the GUI
        'StateChangeConditions', {'Port3In', 'Odor Valves Open', 'Tup', 'Sniff1'},...%When the analog input device detects negative pressure, it sends a digital input to port 3 transitioning to Waiting for Lick.  If it doesn't, return to Sniff1
        'OutputActions', {}); 
    
    sma = AddState(sma, 'Name', 'Odor Valves Open', ...     %Adds a new state called "Odor Valves Open" to the matrix.          
        'Timer', S.GUI.OdorDeliveryTime,...  %Sets timer to for length of time odor should be delivered via the GUI 
        'StateChangeConditions', {'Tup', 'Waiting for Lick'},... %When the timer is up, transitin to Waiting for Lick
        'OutputActions', {'ValveState', ValveToOpen} ); %Opens the dummy(4), final valve(5), and one random vial(6-7).  <Turn off Port 2 and 3 in emulator here?>
    
    sma = AddState(sma, 'Name', 'Waiting for Lick', ...  %Adds a new state to the state machine called waiting for lick
        'Timer', S.GUI.LickWindow,...  %Sets a timer for the time in which a mouse must lick to get water
        'StateChangeConditions', {'Port1In', 'Deliver Reward','Tup', 'Sniff1'},... %When the mouse licks, triggering port1, change state to Deliver Reward.  
        'OutputActions', {});
    
    sma = AddState(sma, 'Name', 'Deliver Reward', ...  %Adds a new state called "Deliver Reward" to the state matrix
        'Timer', S.GUI.RewardAmount,... %Sets timer to deliver reward amount via the GUI
        'StateChangeConditions', {'Tup', 'Sniff1'},... %When the timer is up, return to state 1
        'OutputActions', {'ValveState', 128} ); %Output water reward on valve8
    
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device
    RawEvents = RunStateMatrix; % Run the trial and return events
    
    %--- Package and save the trial's data, update plots
    if ~isempty(fieldnames(RawEvents)) % If you didn't stop the session manually mid-trial
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
        
        %--- Typically a block of code here will update online plots using the newly updated BpodSystem.Data
        
    end
    
    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end