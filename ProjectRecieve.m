%Setup physical layer mode and reciever config for that specific layer mode
phyMode = 'LE2M';
bleParam = helperBLEReceiverConfig(phyMode);
%Create timestamp, API key and channelID for ThingSpeak upload
tStamps = datetime('now');%-minutes(22):minutes(1):datetime('now')]';
channelID = 1009029;
WriteKey = 'Q3DENA88AGK5S6SB';
    
    % First check if the HSP exists
    if isempty(which('plutoradio.internal.getRootDir'))
        error(message('comm_demos:common:NoSupportPackage', ...
                      'Communications Toolbox Support Package for ADALM-PLUTO Radio',...
                      ['<a href="https://www.mathworks.com/hardware-support/' ...
                      'adalm-pluto-radio.html">ADALM-PLUTO Radio Support From Communications Toolbox</a>']));
    end
    
%Setup sample rate and PlutoSDR Recieve object
bbSampleRate = bleParam.SymbolRate * bleParam.SamplesPerSymbol;
sigSrc = sdrrx('Pluto',...
        'RadioID',             'usb:0',...
        'CenterFrequency',     2.402e9,...
        'BasebandSampleRate',  bbSampleRate,...
        'SamplesPerFrame',     1e7,...
        'GainSource',         'Manual',...
        'Gain',                25,...
        'OutputDataType',     'double');

% Setup spectrum viewer
spectrumScope = dsp.SpectrumAnalyzer( ...
    'SampleRate',       bbSampleRate,...
    'SpectrumType',     'Power density', ...
    'SpectralAverages', 10, ...
    'YLimits',          [-130 -30], ...
    'Title',            'Received Baseband BLE Signal Spectrum', ...
    'YLabel',           'Power spectral density');

%%
% *Receiver Processing*
%
% The baseband samples received from the signal source are processed to
% decode the PDU header information and raw message bits.
% Reciever Flow:
% # Perform automatic gain control (AGC)
% # Remove DC offset
% # Estimate and correct for the carrier frequency offset
% # Perform matched filtering with gaussian pulse
% # Timing synchronization
% # GMSK demodulation
% # FEC decoding and pattern demapping for LECoded PHYs (LE500K and LE125K)
% # Data dewhitening
% # Perform CRC check on the decoded PDU
% # Compute packet error rate (PER)

% Initialize System objects for receiver processing
agc = comm.AGC('MaxPowerGain',20,'DesiredOutputPower',2);

freqCompensator = comm.CoarseFrequencyCompensator('Modulation', 'OQPSK',...
                'SampleRate',bbSampleRate,...
                'SamplesPerSymbol',2*bleParam.SamplesPerSymbol,...
                'FrequencyResolution',100);

prbDet = comm.PreambleDetector(bleParam.RefSeq,'Detections','First');

% Initialize counter variables
pktCnt = 0;
crcCnt = 0;
displayFlag = true; % true if the received data is to be printed

% Loop to decode the captured BLE samples

while true 
    
    % *Capture the BLE Packets*
    % The transmitted waveform is captured as a burst
    dataCaptures = sigSrc();
    % Show power spectral density of the received waveform
    spectrumScope(dataCaptures);
    
    while length(dataCaptures) > bleParam.MinimumPacketLen

        % Consider two frames from the captured signal for each iteration
        startIndex = 1;
        endIndex = min(length(dataCaptures),2*bleParam.FrameLength);
        rcvSig = dataCaptures(startIndex:endIndex);

        rcvAGC = agc(rcvSig); % Perform AGC
        rcvDCFree = rcvAGC - mean(rcvAGC); % Remove the DC offset
        rcvFreqComp = freqCompensator(rcvDCFree); % Estimate and compensate for the carrier frequency offset
        rcvFilt = conv(rcvFreqComp,bleParam.h,'same'); % Perform gaussian matched filtering

        % Perform frame timing synchronization
        [~, dtMt] = prbDet(rcvFilt);
        release(prbDet)
        prbDet.Threshold = max(dtMt);
        prbIdx = prbDet(rcvFilt);

        % Extract message information
        [cfgLLAdv,pktCnt,crcCnt,remStartIdx] = helperBLEPhyBitRecover(rcvFilt,...
                                    prbIdx,pktCnt,crcCnt,bleParam);

        % Remaining signal in the burst captures
        dataCaptures = dataCaptures(1+remStartIdx:end);
        
        % Display the decoded information
        if displayFlag && ~isempty(cfgLLAdv)
            disp(hex2dec(cfgLLAdv.AdvertisingData));
                %Write to ThingSpeak cloud API with recieved data. Data can
                %only be written at a delay of 15s 
                 tStamps = datetime('now');
                 thingSpeakWrite(channelID,double(cfgLLAdv.AdvertisingData(end)), 'TimeStamp', tStamps, 'WriteKey', WriteKey);
                 disp('done');
                 pause(15)
        end
        % Release System objects
        release(freqCompensator)
        release(prbDet)
        % Release the signal source
        release(sigSrc)
    
    end 

end