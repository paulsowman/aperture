function list_properties = channel_properties(EEG, eeg_chans, ref_chan)
%CHANNEL_PROPERTIES   Stats on channels for rejection.
%
%  list_properties = channel_properties(EEG, eeg_chans, ref_chan)

% Copyright (C) 2010 Hugh Nolan, Robert Whelan and Richard Reilly, Trinity College Dublin,
% Ireland
% nolanhu@tcd.ie, robert.whelan@tcd.ie
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

%% notes for running on segmented data
% Just using raw channels is a bad idea for an EGI setup with
% impedance checks with crazy voltage recordings. Also, signal
% during breaks is often very erratic, so it would increase noise
% in the analysis if it were included. Want to reject channels
% based on the actual data we're using in the analysis.
%
% This seems to only be an issue for the Hurst exponent measure,
% since it is a temporal measure which will be sensitive to the
% breaks between different epochs. So that needs to be calculated
% within the epochs (preferably not too short), then take the
% median (the distributions I've seen are highly skewed).

if ~isstruct(EEG)
  newdata = EEG;
  clear EEG;
  EEG.data = newdata;
  clear newdata;
end

measure = 1;

if length(ref_chan) == 1
  % distance from the reference channel to each recording channel
  pol_dist = distancematrix(EEG, eeg_chans);
  pol_dist = pol_dist(ref_chan, eeg_chans);
end

% (1) mean correlation between each channel and all other channels
if size(EEG.data, 3) > 1
  % if epoched, calculate correlation for each epoch, so that
  % overall shifts between epochs are not a factor
  mcorrs = NaN(size(EEG.data, 3), length(eeg_chans));
  for i = 1:size(EEG.data, 3)
    % mean correlation with other channels over time within this epoch
    mcorrs(i,:) = nanmean(abs(corrcoef(EEG.data(eeg_chans,:,i)')), 1);
  end
  % for each channel, average over epochs
  mcorrs = nanmean(mcorrs, 1);
else
  % mean correlation with other channels over time
  mcorrs = nanmean(abs(corrcoef(EEG.data(eeg_chans,:)')), 1);
end

% quadratic correction for distance from reference electrode
if length(ref_chan) == 1
  bad = isnan(mcorrs);
  mcorrs(~bad) = correct_ref_dist(pol_dist(~bad), mcorrs(~bad));
end

list_properties(:,measure) = mcorrs;
measure = measure + 1;

% (2) variance of the channels
vars = var(EEG.data(eeg_chans,:)');
vars(~isfinite(vars)) = mean(vars(isfinite(vars)));

% quadratic correction for distance from reference electrode
if length(ref_chan) == 1
  vars = correct_ref_dist(pol_dist, vars);
end

list_properties(:,measure) = vars;
measure = measure + 1;

% (3) Hurst exponent
for u = 1:length(eeg_chans)
  if size(EEG.data, 3) > 1
    % if epoched data, calculate for each epoch and take the median
    hurst_epoch = NaN(1, size(EEG.data, 3));
    for i = 1:size(EEG.data, 3)
      hurst_epoch(i) = hurst_exponent(EEG.data(eeg_chans(u),:,i));
    end
    list_properties(u,measure) = median(hurst_epoch);
  else
    % continous data
    list_properties(u,measure) = hurst_exponent(EEG.data(eeg_chans(u),:));
  end
end

for u = 1:size(list_properties, 2)
  % set undefined stats to the mean over the other channels
  list_properties(isnan(list_properties(:,u)),u) = ...
      nanmean(list_properties(:,u));
  
  % subtract out the median of each property
  list_properties(:,u) = list_properties(:,u) - median(list_properties(:,u));
end