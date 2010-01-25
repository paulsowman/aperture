function subj = classify_pat2pat(subj, train_pat_name, test_pat_name, ...
                                 stat_name, varargin)
%CLASSIFY_PAT2PAT   Train a classifier on one pattern and test on another.
%
%  Train a classifier on a pattern and test on another pattern. For each
%  dimension of the patterns (except events) there are possibilities:
%   1) iterate over all values, training and testing on each element.
%      The sizes of the patterns along the dimension must match.
%   2) same as (1), but iterate over groups, rather than individual
%      elements. Classification will be done for each group, and all
%      elements in the group will be features of the pattern. Patterns
%      must have the same number of groups along the dimension.
%   3) train and test on all values of the dimension, using all values
%      as features in the patterns. The sizes of the patterns along
%      the dimension must match.
%  params.iter_cell specifies how to iterate over both the train and
%  test patterns.
%
%  All events must be passed in (i.e. no iterating or grouping), but
%  the events dimension is included in iter_cell for consistency, i.e.
%  the channels dimension is iter_cell{2}, and iter_cell{1} must always
%  be empty.
%
%  If params.sweep_cell is specified, additional partitioning will be
%  done to the test pattern.  This will only work in cases where a
%  dimension is singleton in the training pattern, and you want to sweep
%  over that dimension in the test pattern.  You cannot, for example,
%  iterate over the time bins of the training pattern, and for each of
%  those training time bins, sweep over all testing time bins.  You must
%  pick one training time bin (or average over multiple bins) first,
%  and modify the training pattern before passing it to this function so
%  there is only one training time bin.  Then you can train the
%  classifier on the training pattern, and test on all the time bins of
%  the test pattern.
%
%  subj = classify_pat2pat(subj, train_pat_name, test_pat_name, stat_name, ...)
%
%  INPUTS:
%            subj:  a subject object.
%
%  train_pat_name:  the name of a training pattern, attached to the
%                   subject object.
%
%   test_pat_name:  the name of a test pattern, attached to the subject
%                   object.
%
%       stat_name:  name of the stat object that will be created to hold
%                   results of the analysis. Default: 'patclass'
%
%  OUTPUTS:
%            subj:  modified subject object with an added stat object
%                   that contains the results of the analysis.
%
%  PARAMS:
%  These options may be specified using parameter, value pairs or by
%  passing a structure. Defaults are shown in parentheses.
%   regressor    - REQUIRED - input to make_event_bins; used to create
%                  the regressor for classification.
%   iter_cell    - determines which dimensions to iterate over for both
%                  training and testing. See apply_by_group for details.
%                  Default is to train on all features of the training
%                  pattern at once and test on all features of the
%                  testing pattern. May also input a params struct to be
%                  passed into patBins to create grouped dimensions.
%                  ({[],[],[],[]})
%   sweep_cell   - determines which dimension to iterate over for
%                  testing only. See apply_by_group (iter_cell) for
%                  details. Default is to test on the same dimensions
%                  as the training pattern. In this case, all dimensions
%                  of the train and test patterns must match. May also
%                  input a params struct to be passed into patBins to
%                  create a grouped dimension. ({[],[],[],[]})
%   f_train      - function handle for a training function.
%                  (@train_logreg)
%   train_args   - struct with options for f_train. (struct)
%   f_test       - function handle for a testing function.
%                  (@test_logreg)
%   f_perfmet    - function handle for a function that calculates
%                  classifier performance. Can also pass a cell array
%                  of function handles, and all performance metrics will
%                  be calculated. ({@perfmet_maxclass})
%   perfmet_args - cell array of additional arguments to f_perfmet
%                  function(s). ({struct})
%   overwrite    - if true, if the stat file already exists, it will be
%                  overwritten. (true)
%   res_dir      - directory in which to save the classification
%                  results. Default is the test pattern's stats
%                  directory.
%
%  See also classify_pat.

% input checks
if ~exist('subj', 'var') || ~isstruct(subj)
  error('You must pass a subject object.')
elseif ~exist('train_pat_name', 'var') || ~ischar(train_pat_name)
  error('You must give the name of a training pattern.')
elseif ~exist('test_pat_name', 'var') || ~ischar(test_pat_name)
  error('You must give the name of a test pattern.')
end
if ~exist('stat_name', 'var')
  stat_name = 'patclass';
end

% get the pat objects
train_pat = getobj(subj, 'pat', train_pat_name);
test_pat = getobj(subj, 'pat', test_pat_name);

% set default params
defaults.regressor = '';
defaults.iter_cell = cell(1, 4);
defaults.sweep_cell = cell(1, 4);
defaults.overwrite = true;
defaults.res_dir = get_pat_dir(test_pat, 'stats');
params = propval(varargin, defaults, 'strict', false);

if isempty(params.regressor)
  error('You must specify a regressor in params.')
end

% set where the results will be saved
stat_file = fullfile(params.res_dir, objfilename(train_pat.name, stat_name, ...
                                                 train_pat.source));

% check the output file
if ~params.overwrite && exist(stat_file, 'file')
  return
end

% dynamic grouping
if isstruct(params.iter_cell)
  % make bins using the train pattern (shouldn't matter which we use)
  [temp, params.iter_cell] = patBins(train_pat, params.iter_cell);
end
if isstruct(params.sweep_cell)
  % make bins from the test pattern
  [temp, params.sweep_cell] = patBins(test_pat, params.sweep_cell);
end

% make sure user isn't trying to group events
if ~isempty(params.iter_cell{1}) || ~isempty(params.sweep_cell{1})
  error('Iterating and grouping is not supported for the events dimension.')
end

% one can save extra information in params, like the set of
% groupnames that were used to make a set of channel groups.
stat = init_stat(stat_name, stat_file, train_pat.source, params);

% get events for both patterns
train_events = get_dim(train_pat.dim, 'ev');
test_events = get_dim(test_pat.dim, 'ev');

% the correct answers for classification
train_targs = create_targets(train_events, params.regressor);
test_targs = create_targets(test_events, params.regressor);

% load the patterns themselves
train_pattern = get_mat(train_pat);
test_pattern = get_mat(test_pat);

% the outer level of slicing
res.iterations = apply_by_group(@sweep_wrapper, ...
                                {train_pattern, test_pattern}, ...
                                params.iter_cell, ...
                                {train_targs, test_targs, params}, ...
                                'uniform_output', false);

% this unraveling seems to work for fsweep and tsweep
res = unravel_res(res);

% save the results to disk
save(stat.file, 'res');

% add the stat object to the output pat object
subj = setobj(subj, 'pat', test_pat_name, 'stat', stat);

function res = sweep_wrapper(train_pattern, test_pattern, ...
                             train_targs, test_targs, params);
% SWEEP_WRAPPER
%
%

% the inner level of sweeping
res = apply_by_group(@traintest, {test_pattern}, ...
                     params.sweep_cell, ...
                     {train_pattern, test_targs, train_targs, params}, ...
                     'uniform_output', false);


function res = unravel_res(res)
%UNRAVEL_RES   Reformat res to be a structure array.
%
%  res = unravel_res(res)

N_DIMS = 4;

% get size of outer cell array and inner cell arrays
outer_loop_size = size(res.iterations);
inner_loop_size = size(res.iterations{1});

% pad if necessary
if length(outer_loop_size) < N_DIMS
  outer_loop_size(end+1:N_DIMS) = 1;
end
if length(inner_loop_size) < N_DIMS
  inner_loop_size(end+1:N_DIMS) = 1;
end

% initialize the output
f = fieldnames(res.iterations{1}{1});
s = cell2struct(cell(1, length(f)), f, 2);
temp = repmat(s, [outer_loop_size inner_loop_size]);

% unravel
outer_sub = cell(1, N_DIMS);
inner_sub = cell(1, N_DIMS);
for i=1:prod(outer_loop_size)
  for j=1:prod(inner_loop_size)
    [outer_sub{:}] = ind2sub(outer_loop_size, i);
    [inner_sub{:}] = ind2sub(inner_loop_size, j);
    temp(outer_sub{:}, inner_sub{:}) = res.iterations{i}{j};
  end
end

% move inner to outer if we did any sweeping
new_outer = NaN(1, N_DIMS);
new_inner = NaN(1, N_DIMS);
for i=1:N_DIMS
  % size of inner and outer loops
  out = outer_loop_size(i);
  in = inner_loop_size(i);
  
  % index in the struct array
  out_index = i;
  in_index = i + N_DIMS;
  
  if out > 1 && in > 1
    error(['Unexpected: both outer and inner size of dim %d is ' ...
           'non-singleton.'], i)
  elseif out > 1 || (out == 1 && in == 1)
    % outer is non-singleton, inner is not; don't need to flip
    new_outer(i) = out_index;
    new_inner(i) = in_index;
  elseif in > 1
    % inner is non-singleton; need to flip with corresponding outer
    new_outer(i) = in_index;
    new_inner(i) = out_index;
  end
end
temp = permute(temp, [new_outer new_inner]);

res.iterations = temp;

