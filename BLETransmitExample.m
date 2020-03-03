array = ["Loop1","Loop2"]

% Symbol rate based on |'Mode'|
symbolRate = 1e6;
%if strcmp(phyMode,'LE2M')
    %symbolRate = 2e6;
%end
%Configure an advertising channel PDU
 cfgLLAdv = bleLLAdvertisingChannelPDUConfig;
 cfgLLAdv.PDUType = 'Advertising indication';
 cfgLLAdv.AdvertiserAddress = '1234567890AB';

 phyMode = 'LE1M'; % Select one mode from the set {'LE1M','LE2M','LE500K','LE125K'}
 sps = 8;          % Samples per symbol
 channelIdx = 37;  % Channel index value in the range [0,39]
 accessAddLen = 32;% Length of access address
 accessAddHex = '8E89BED6';  % Access address value in hexadecimal
 accessAddBin = de2bi(hex2dec(accessAddHex),accessAddLen)'; % Access address in binary

    % First check if the HSP exists
    if isempty(which('plutoradio.internal.getRootDir'))
        error(message('comm_demos:common:NoSupportPackage', ...
                      'Communications Toolbox Support Package for ADALM-PLUTO Radio',...
                      ['<a href="https://www.mathworks.com/hardware-support/' ...
                      'adalm-pluto-radio.html">ADALM-PLUTO Radio Support From Communications Toolbox</a>']));
    end
    connectedRadios = findPlutoRadio; % Discover ADALM-PLUTO radio(s) connected to your computer
    radioID = connectedRadios(1).RadioID;
    
for n = 1 : length(array)
    
    cfgLLAdv.AdvertisingData = dec2hex('n');
    messageBits = bleLLAdvertisingChannelPDU(cfgLLAdv);
    disp('Data Configured')

    % Generate BLE waveform
    txWaveform = bleWaveformGenerator(messageBits,...
        'Mode',            phyMode,...
        'SamplesPerSymbol',sps,...
        'ChannelIndex',    channelIdx,...
        'AccessAddress',   accessAddBin);
    disp('Waveform Generated')

    % Setup spectrum viewer
    spectrumScope = dsp.SpectrumAnalyzer( ...
        'SampleRate',       symbolRate*sps,...
        'SpectrumType',     'Power density', ...
        'SpectralAverages', 10, ...
        'YLimits',          [-130 0], ...
        'Title',            'Baseband BLE Signal Spectrum', ...
        'YLabel',           'Power spectral density');
    disp('Viewer Generated')
    
    % Show power spectral density of the BLE signal
    spectrumScope(txWaveform);
    
    % Initialize the parameters required for signal source
    txCenterFrequency       = 2.402e9;  % Varies based on channel index value
    txFrameLength           = length(txWaveform);
    txNumberOfFrames        = 1e4;
    txFrontEndSampleRate    = symbolRate*sps;
    
    sigSink = sdrtx( 'Pluto',...
        'RadioID',           radioID,...
        'CenterFrequency',   txCenterFrequency,...
        'Gain',              0,...
        'SamplesPerFrame',   txFrameLength,...
        'BasebandSampleRate',txFrontEndSampleRate);
    currentFrame = 1;
    try
        while currentFrame <= txNumberOfFrames
            % Data transmission
            sigSink(txWaveform);
            % Update the counter
            currentFrame = currentFrame + 1;
            disp(currentFrame)
        end
    catch ME
        release(sigSink);
        rethrow(ME)
    end
% Release the signal sink
release(sigSink)
end
