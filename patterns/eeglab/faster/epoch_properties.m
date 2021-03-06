function list_properties = epoch_properties(EEG, eeg_chans)
%LIST_PROPERTIES   Stats on epochs for rejection.
%
%  list_properties = epoch_properties(EEG, eeg_chans)

list_properties = [];

if length(size(EEG.data)) < 3
  fprintf('Not epoched.\n');
  return
end

measure = 1;

% mean over time and all epochs, for each channel
means = mean(EEG.data(eeg_chans,:), 2);

% 1 Epoch's mean deviation from channel means
for u = 1:size(EEG.data, 3)
  list_properties(u,measure) = mean(abs(squeeze(mean(EEG.data(eeg_chans,:,u),2)) - means));
end
measure = measure + 1;

% 2 Epoch variance
list_properties(:,measure) = mean(squeeze(var(EEG.data(eeg_chans,:,:),0,2)));
measure = measure + 1;

% 3 Max amplitude difference
ampdiffs = epoch_amp_diff(EEG, eeg_chans);
list_properties(:,measure) = median(ampdiffs, 1);

measure = measure + 1;

% % 4 Median gradient
% for t = eeg_chans
%   for u = 1:size(EEG.data,3)
%     % instead of global max - global min, get the median absolute
%     % change between adjacent samples; this may be better for
%     % identifying epochs with many smaller changes (e.g. large EMG
%     % activity, widespread signal flailing)
%     ampdiffs(t,u) = median(abs(diff(EEG.data(t,:,u), [], 2)), 2);
%   end
% end
% list_properties(:,measure) = mean(ampdiffs,1);
% measure = measure + 1;

for v = 1:size(list_properties, 2)
  list_properties(:,v) = list_properties(:,v) - median(list_properties(:,v));
end