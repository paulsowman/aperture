function pattern = sessVoltage(pat,bins,events,base_events)
%SESSVOLTAGE   Create a voltage pattern for one session.
%   PATTERN = SESSVOLTAGE(PAT,BINS,EVENTS,BASE_EVENTS)
%
%   Params:
%     'relativeMS'
%     'baseOffsetMS'
%     'baseDurationMS'
%     'filttype'
%     'filtfreq'
%     'filtorder'
%     'bufferMS'
%     'kthresh'
%     'ztransform'
%
%   See also create_pattern, sessPower.
%

% set defaults for pattern creation
params = structDefaults(pat.params, 'relativeMS', [],  'baseOffsetMS', -200,  'baseDurationMS', 100, 'filttype', 'stop',  'filtfreq', [58 62],  'filtorder', 4,  'bufferMS', 1000,  'kthresh', 5,  'ztransform', 1, 'artWindow',500);

if ~isfield(params,'baseRelativeMS')
  params.baseRelativeMS = params.relativeMS;
end

timebins = makeBins(1000/params.resampledRate,params.offsetMS,params.offsetMS+params.durationMS);

% initialize the pattern for this session
pattern = NaN(length(events), length(params.channels), length(pat.dim.time));

fprintf('Channels: ')
for c=1:length(params.channels)
	fprintf('%d ', params.channels(c));

	% get baseline stats for this channel, sess
	if params.ztransform
		base_eeg = gete_ms(params.channels(c), base_events, ...
		params.baseDurationMS, params.baseOffsetMS, params.bufferMS, ... 
		params.filtfreq, params.filttype, params.filtorder, ...
		params.resampledRate, params.baseRelativeMS);

		if ~isempty(params.kthresh)
			k = kurtosis(base_eeg,1,2);
			base_eeg = base_eeg(k<=params.kthresh,:);
		end

		% if multiple samples given, use the first
		base_eeg_vec = base_eeg(:,1);
		base_mean = nanmean(base_eeg_vec);
		base_std = nanstd(base_eeg_vec);   
	end

	% get power, z-transform, average each time bin
	for e=1:length(events)
		this_eeg = squeeze(gete_ms(params.channels(c), events(e), ...
		params.durationMS, params.offsetMS, params.bufferMS, ...
		params.filtfreq, params.filttype, params.filtorder, ...
		params.resampledRate, params.relativeMS));

		% check kurtosis for this event, add info to boolean mask for later
		if ~isempty(params.kthresh)
			k = kurtosis(this_eeg);
			if k>params.kthresh
			  this_eeg(:) = NaN;
		  end
			%this_eeg(k>params.kthresh) = NaN;
		end

		% normalize across sessions
		if params.ztransform
			this_eeg = (this_eeg - base_mean)/base_std;
		end
		
		if ~isempty(params.artWindow)
		  art = markArtifacts(events(e), timebins, params.artWindow);
		  this_eeg(art) = NaN;
	  end
		
		% add this event/channel to the pattern
		pattern(e,c,:) = patMeans(this_eeg(:), bins(3));
		
	end % events

end % channel

% time already binned, events will be binned later
bins([1 3]) = {[]};

% bin channels
pattern = patMeans(pattern, bins);


function 
