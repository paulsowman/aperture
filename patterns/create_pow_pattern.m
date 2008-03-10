function exp = create_pow_pattern(exp, params, patname, resDir)
%exp = create_pow_pattern(exp, params, patname, resDir)
%
% create a power pattern for each subject, time bin, saved in
% resDir/data.  Filenames will be saved in exp.subj(s).pat
% with the patname specified.
%

if ~exist('patname', 'var')
  patname = 'power_pattern';
end
if ~exist('resDir', 'var')
  resDir = fullfile(exp.resDir, patname);
end

% set the defaults for params
params = structDefaults(params,  'evname', 'events',  'eventFilter', '',  'freqs', 2.^(1:(1/8):6),  'offsetMS', -200,  'durationMS', 1800,  'binSizeMS', 100,  'baseEventFilter', '',  'baseOffsetMS', -200,  'baseDurationMS', 200,  'filttype', 'stop',  'filtfreq', [58 62],  'filtorder', 4,  'bufferMS', 1000,  'resampledRate', 500,  'width', 6,  'kthresh', 5,  'ztransform', 1,  'logtransform', 0,  'replace_eegFile', {},  'timebinlabels', {},  'freqbinlabels', {},  'lock', 1  'overwrite', 0);

% get bin information
durationSamp = fix(params.durationMS*params.resampledRate./1000);
binSizeSamp = fix(params.binSizeMS*params.resampledRate./1000);
nBins = fix(durationSamp/binSizeSamp);

% initialize the time dimension
binSamp{1} = [1:binSizeSamp];
for b=2:nBins
  binSamp{b} = binSamp{b-1} + binSizeSamp;
end

for t=1:length(binSamp)
  time(t).MSvals = fix((binSamp{t}-1)*1000/params.resampledRate) + params.offsetMS;
  time(t).avg = mean(time(t).MSvals);
  if ~isempty(params.timebinlabels)
    time(t).label = params.timebinlabels{t};
  else
    time(t).label = [num2str(time(t).MSvals(1)) ' to ' num2str(time(t).MSvals(end)) 'ms'];
  end
end

% initialize the frequency dimension
for f=1:length(params.freqs)
  freq(f).vals = params.freqs(f);
  freq(f).avg = mean(freq(f).vals);
  if ~isempty(params.freqbinlabels)
    freq(f).label = params.freqbinlabels{f};
  else
    freq(f).label = [num2str(freq(f).vals) 'Hz'];
  end
end

disp(params);

rand('twister',sum(100*clock));

% write all file info and update the exp struct
for s=1:length(exp.subj)
  pat.name = patname;
  pat.file = fullfile(resDir, 'data', [patname '_' exp.subj(s).id '.mat']);
  pat.params = params;
  
  % manage the dimensions info
  pat.dim = struct('event', [],  'chan', [],  'time', [],  'freq', []);
  
  pat.dim.event.num = [];
  pat.dim.event.file = fullfile(resDir, 'data', [patname '_' exp.subj(s).id '_events.mat']);
  
  if isfield(params, 'channels')
    pat.dim.chan = filterStruct(exp.subj(s).chan, 'ismember(number, varargin{1})', params.channels);
  else
    pat.dim.chan = exp.subj(s).chan;
  end
  pat.dim.time = time;
  pat.dim.freq = freq;
  
  % update exp with the new pat object
  exp = update_exp(exp, 'subj', exp.subj(s).id, 'pat', pat);
end

% make the pattern for each subject
for s=1:length(exp.subj)
  pat = getobj(exp.subj(s), 'pat', patname);
  
  % see if this subject has been done
  if prepFiles({}, pat.file, params)~=0
    continue
  end
  
  % get all events for this subject, w/filter that will be used to get voltage
  ev = getobj(exp.subj(s), 'ev', evname);
  events = loadEvents(ev.file, params.replace_eegfile);
  base_events = filterStruct(events(:), params.baseEventFilter);
  events = filterStruct(events(:), params.eventFilter);

  % get some stats
  pat.dim.event.num = length(events);
  sessions = unique(getStructField(events, 'session'));
  channels = getStructField(pat.dim.chan, 'number');
  
  % initialize this subject's pattern
  patSize = [pat.dim.event.num, length(pat.dim.chan), length(pat.dim.time), length(pat.dim.freq)];
  pattern = NaN(patSize);
  
  % set up masks
  m = 1;
  mask(m).name = 'bad_channels';
  mask(m).mat = false(patSize);
  if ~isempty(params.kthresh)
    mask(m).name = 'kurtosis';
    mask(m).mat = false(patSize);
    m = m + 1;
  end
  if isfield(params, 'artWindow') && ~isempty(params.artWindow)
    mask(m).name = 'artifacts';
    mask(m).mat = false(patSize);

    artMask = rmArtifacts(events, time, params.artWindow);
    for c=1:size(mask(m),2)
      mask(m).mat(:,c,:) = artMask;
    end
  end
  
  % get the patterns for each frequency and time bin
  start_e = 1;
  for n=1:length(exp.subj(s).sess)
    fprintf('\n%s', exp.subj(s).sess(n).eventsFile);
    this_sess = inStruct(events, 'session==varargin{1}', sessions(n));
    sess_events = events(this_sess);
    sess_base_events = filterStruct(base_events, 'session==varargin{1}', sessions(n));
    
    % make bad channels mask
    bad = setdiff(channels, exp.subj(s).sess(n).goodChans);
    mask(1).mat(this_sess, bad, :) = 1;
    
    for c=1:length(channels)
      fprintf('%d.', channels(c));
      
      % if z-transforming, get baseline stats for this sess, channel
      if params.ztransform
	base_pow = getphasepow(channels(c), sess_base_events, ...
	                       params.baseDurationMS, ...
			       params.baseOffsetMS, params.bufferMS, ... 
			       'freqs', params.freqs, ... 
			       'filtfreq', params.filtfreq, ... 
			       'filttype', params.filttype, ...
			       'filtorder', params.filtorder, ... 
			       'kthresh', params.kthresh, ...
			       'width', params.width, ...
                               'resampledRate', params.resampledRate, ...
			       'powonly');
	  
	% do log transform if desired
	if params.logtransform
	  base_pow(base_pow<=0) = eps(0);
	  base_pow = log10(base_pow);
	end
	  
	for f=1:length(freqs)
	  % if multiple samples given, use the first
	  base_pow_vec = base_pow(:,f,1);
	  
	  % get separate baseline stats for each freq
	  base_mean(f) = nanmean(base_pow_vec);
	  base_std(f) = nanstd(base_pow_vec);
	end
      end % baseline
	
      % get power, z-transform, average each time bin
      e = start_e;
      for sess_e=1:length(sess_events)
	
	[this_pow, kInd] = getphasepow(channels(c), sess_events(sess_e), ...
				     params.durationMS, ...
			             params.offsetMS, params.bufferMS, ... 
			             'freqs', params.freqs, ... 
				     'filtfreq', params.filtfreq, ... 
				     'filttype', params.filttype, ...
				     'filtorder', params.filtorder, ... 
				     'kthresh', params.kthresh, ...
				     'width', params.width, ...
                                     'resampledRate', params.resampledRate, ...
			             'powonly', 'keepk');   
	
	% make it time X frequency
	this_pow = shiftdim(squeeze(this_pow),1);
	
	for f=1:length(params.freqs)
	  % add kurtosis information to the mask
	  mask(1).mat(e,c,:,f) = kInd;

	  if params.ztransform
	    if params.logtransform
	      this_pow(this_pow<=0) = eps(0);
	      this_pow = log10(this_pow);
	    end
	    
	    % z-transform
	    this_pow = (this_pow - base_mean(f))/base_std(f);
	  end
	end
	
	% average over adjacent time bins
	if ~isempty(this_pow)
	  for b=1:nBins
	    pattern(e,c,b,:) = nanmean(this_pow(binSamp{b},:));
	  end
	end
	
	e = e + 1;
      end % events
      
    end % channel
    start_e = start_e + length(sess_events);
    
  end % session
  fprintf('\n');
  
  % save the pattern and corresponding events struct and masks
  closeFile(pat.file, 'pattern', 'mask');
  save(pat.dim.event.file, 'events');
  
  % added event info to pat, so update exp again
  exp = update_exp(exp, 'subj', exp.subj(s).id, 'pat', pat);
end % subj




