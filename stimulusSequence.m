classdef stimulusSequence < optickaCore & dynamicprops
	properties
		%> whether to randomise (true) or run sequentially (false)
		randomise = true
		%> structure holding each independant variable
		nVar = []
		%> number of repeat blocks to present
		nBlocks = 1
		%> time stimulus trial is shown
		trialTime = 2
		%> inter stimulus trial time
		isTime = 1 
		%> inter block time
		ibTime = 2
		%> what do we show in the blank?
		isStimulus
		%> do we follow real time or just number of ticks to get to a known time
		realTime = true
		%> random seed value, we can use this to set the RNG to a known state
		randomSeed
		%> mersenne twister default
		randomGenerator='mt19937ar' 
		%> used for dynamically estimating total number of frames
		fps = 60 
		%> will be used when we extend each trial to have sub-segments
		nSegments = 1 
		%> segment info
		nSegment
		%> verbose or not
		verbose = false
	end
	
	properties (SetAccess = private, GetAccess = public)
		%> structure of variable values
		outValues 
		%> variable values wrapped in trial cell
		outVars 
		%> the unique identifier for each stimulus
		outIndex = 1
		%> mapping the stimulus to the number as a X Y and Z etc position for display
		outMap
		%> minimum number of blocks
		minBlocks
		%> reserved for future use of multiple random stream states
		states
		%> reserved for future use of multiple random stream states
		nStates = 1
	end
	
	properties (SetAccess = private, GetAccess = public, Transient = true)
		%> old random number stream
		oldStream
		%> current random number stream
		taskStream
		%> current random stream state
		currentState
	end
	
	properties (Dependent = true,  SetAccess = private)
		%> number of blocks, need to rename!
		nRuns 
		%> estimate of the total number of frames this task will occupy,
		%> requires accurate fps 
		nFrames 
		%> number of independant variables
		nVars = 0
	end
	
	properties (SetAccess = private, GetAccess = private)
		%> cache value for nVars
		nVars_
		%> handles from obj.showLog
		h
		%> properties allowed during initial construction
		allowedProperties='randomise|nVar|nBlocks|trialTime|isTime|ibTime|realTime|randomSeed|fps'
		%> used to handle problems with dependant property nVar: the problem is
		%> that set.nVar gets called before static loadobj, and therefore we need
		%> to handle this differently. Initially set to empty, set to true when
		%> running loadobj() and false when not loading object.
		isLoading = []
		%> properties used by loadobj when a structure is passed during load.
		%> this stops loading old randstreams etc.
		loadProperties = {'randomise','nVar','nBlocks','trialTime','isTime','ibTime','isStimulus','verbose',...
			'realTime','randomSeed','randomGenerator','nSegments','nSegment'}
		%Set up the task structures needed
		taskProperties = {'tick',0,'blankTick',0,'thisRun',1,'thisBlock',1,'totalRuns',1,'isBlank',false,...
				'switched',false,'strobeThisFrame',false,'doUpdate',false,'startTime',0,'switchTime',0,...
				'switchTick',0,'timeNow',0,'stimIsDrifting',[],'stimIsMoving',[],...
				'stimIsDots',[],'stimIsFlashing',[]}
	end
	
	
	methods
		% ===================================================================
		%> @brief Class constructor
		%>
		%> Send any parameters to parseArgs.
		%>
		%> @param varargin are passed as a structure of properties which is
		%> parsed.
		%> @return instance of the class.
		% ===================================================================
		function obj = stimulusSequence(varargin) 
			if nargin > 0
				obj.parseArgs(varargin,obj.allowedProperties)
			end
			obj.mversion = str2double(regexp(version,'(?<ver>^\d+\.\d+)','match','once'));
			obj.initialiseRandom();
			obj.isLoading = false;
		end
		
		% ===================================================================
		%> @brief set up the random number generator
		%>
		%> set up the random number generator
		% ===================================================================
		function initialiseRandom(obj)
			if obj.verbose==true;tic;end
			if isnan(obj.mversion)
				obj.mversion = str2double(regexp(version,'(?<ver>^\d+\.\d+)','match','once'));
			end
			if isempty(obj.randomSeed)
				obj.randomSeed=round(rand*sum(clock));
			end
			if isempty(obj.oldStream)
				if obj.mversion > 7.11
					obj.oldStream = RandStream.getGlobalStream;
				else
					obj.oldStream = RandStream.getDefaultStream; %#ok<*GETRS>
				end
			end
			obj.taskStream = RandStream.create(obj.randomGenerator,'Seed',obj.randomSeed);
			if obj.mversion > 7.11
				RandStream.setGlobalStream(obj.taskStream);
			else
				RandStream.setDefaultStream(obj.taskStream); %#ok<*SETRS>
			end
			if obj.verbose==true;obj.salutation(sprintf('Initialise Randomisation: %g milliseconds',toc/1000));end
		end
		
		% ===================================================================
		%> @brief Reset the random number generator
		%>
		%> reset the random number generator
		% ===================================================================
		function resetRandom(obj)
			obj.randomSeed=[];
			if obj.mversion > 7.11
				RandStream.setGlobalStream(obj.oldStream);
			else
				RandStream.setDefaultStream(obj.oldStream);
			end
		end
		
		% ===================================================================
		%> @brief Do the randomisation
		%>
		%> Do the randomisation
		% ===================================================================
		function randomiseStimuli(obj)
			if obj.nVars > 0 %no need unless we have some variables
				if obj.verbose==true;tic;end
				obj.currentState=obj.taskStream.State;
				%obj.states(obj.nstates) = obj.currentState;
				%obj.nstates = obj.nstates + 1;

				nLevels = zeros(obj.nVars, 1);
				for f = 1:obj.nVars
					nLevels(f) = length(obj.nVar(f).values);
				end

				obj.minBlocks = prod(nLevels);
				if isempty(obj.minBlocks)
					obj.minBlocks = 1;
				end
				if obj.minBlocks > 2046
					warndlg('WARNING: You are exceeding the number of stimuli the Plexon can identify!')
				end

				% initialize cell array that will hold balanced variables
				obj.outVars = cell(obj.nBlocks, obj.nVars_);
				obj.outValues = [];
				obj.outIndex = [];

				% the following initializes and runs the main loop in the function, which
				% generates enough repetitions of each factor, ensuring a balanced design,
				% and randomizes them
				offset=0;
				for i = 1:obj.nBlocks
					len1 = obj.minBlocks;
					len2 = 1;
					if obj.randomise == true
						[~, index] = sort(rand(obj.minBlocks, 1));
					else
						index = (1:obj.minBlocks)';
					end
					obj.outIndex = [obj.outIndex; index];
					for f = 1:obj.nVars
						len1 = len1 / nLevels(f);
						if size(obj.nVar(f).values, 1) ~= 1
							% ensure that factor levels are arranged in one row
							obj.nVar(f).values = reshape(obj.nVar(f).values, 1, numel(obj.nVar(1).values));
						end
						% this is the critical line: it ensures there are enough repetitions
						% of the current factor in the correct order
						obj.outVars{i,f} = repmat(reshape(repmat(obj.nVar(f).values, len1, len2), obj.minBlocks, 1), obj.nVars_, 1);
						obj.outVars{i,f} = obj.outVars{i,f}(index);
						len2 = len2 * nLevels(f);
						mn=offset+1;
						mx=i*obj.minBlocks;
						obj.outValues(mn:mx,f)=obj.outVars{i,f};
					end
					offset=offset+obj.minBlocks;
				end
				obj.outMap=zeros(size(obj.outValues));
				for f = 1:obj.nVars_
					for g = 1:length(obj.nVar(f).values)
						gidx = obj.outValues(:,f) == obj.nVar(f).values(g);
						obj.outMap(gidx,f) = g;
					end
				end
				if obj.verbose==true;obj.salutation(sprintf('Randomise Stimuli: %g ms\n',toc*1000));end
			else
				obj.outIndex = 1; %there is only one stimulus, no variables
			end
		end
		
		% ===================================================================
		%> @brief Initialise the properties used to track the run
		%>
		%> Initialise the properties used to track the run. These are dynamic
		%> props and are set to be transient so they are not saved.
		% ===================================================================
		function initialiseTask(obj)
			for i = 1:2:length(obj.taskProperties)
				if isempty(obj.findprop(obj.taskProperties{i}))
					p=obj.addprop(obj.taskProperties{i}); %add new dynamic property
					p.Transient = true;
				end
				obj.(obj.taskProperties{i})=obj.taskProperties{i+1}; %#ok<*MCNPR>
			end
		end
		
		% ===================================================================
		%> @brief validate the stimulusSequence is ok
		%>
		%> Check we have a minimal task structure
		% ===================================================================
		function validate(obj)
			
			vin = obj.nVar;
			vout = vin;
			obj.nVar = [];
			shift = 0;
			
			for i = 1:length(vin)
				if isempty(vin(i).name)
					vout(i + shift) = [];
					shift = shift-1;
				end
			end
			
			obj.nVar = vout;
			
			clear vin vout shift
			
			if obj.nVars == 0
				obj.outIndex = 1; %there is only one stimulus, no variables
			end
		
		end
		
		% ===================================================================
		%> @brief set method for the nVar structure
		%>
		%> Check we have a minimal nVar structure and deals new values
		%> appropriately.
		% ===================================================================
		function set.nVar(obj,invalue)
			if obj.isLoading == false %this stops set being called unexpectedly
				obj.nVar = invalue;
				return;
			end
			varTemplate = struct('name','','stimulus',0,'values',[],'offsetstimulus',[],'offsetvalue',[]);
			if ~exist('invalue','var')
				invalue = [];
			end
			if obj.isLoading == true && isstruct(invalue) %#ok<*MCSUP>
				obj.nVar = invalue;
				if ~isfield(obj.nVar,'offsetstimulus') || ~isfield(obj.nVar,'offsetvalue') %add to old versions of nVar
					obj.nVar(1).offsetstimulus = [];
					obj.nVar(1).offsetvalue = [];
				end
				return;
			end
			if isempty(obj.nVar) || isempty(invalue)
				obj.nVar = varTemplate;
			elseif isstruct(obj.nVar) && isempty(fieldnames(obj.nVar))
				obj.nVar = varTemplate;
			end
			if ~isempty(invalue) && isstruct(invalue)
				idx = length(invalue);
				invalue = invalue(idx);
				fn = fieldnames(invalue);
				for i = 1:length(fn)
					if isfield(obj.nVar(1), fn{i}) && ~isempty(invalue.(fn{i}));
						obj.nVar(idx).(fn{i}) = invalue.(fn{i});
					end
				end
			end
		end
		
		% ===================================================================
		%> @brief Dependent property nRuns get method
		%>
		%> Dependent property nruns get method
		% ===================================================================
		function nVars = get.nVars(obj)
			nVars = 0;
			if length(obj.nVar) > 0 && ~isempty(obj.nVar(1).name) %#ok<ISMT>
				nVars = length(obj.nVar);
			end
			obj.nVars_ = nVars;
		end
		
		% ===================================================================
		%> @brief Dependent property nRuns get method
		%>
		%> Dependent property nruns get method
		% ===================================================================
		function nRuns = get.nRuns(obj)
			nRuns = obj.minBlocks*obj.nBlocks;
		end
		
		% ===================================================================
		%> @brief Dependent property nFrames get method
		%>
		%> Dependent property nFrames get method
		% ===================================================================
		function nFrames = get.nFrames(obj)
			nSecs = (obj.nRuns * obj.trialTime) + (obj.minBlocks-1 * obj.isTime) + (obj.nBlocks-1 * obj.ibTime);
			nFrames = ceil(nSecs) * ceil(obj.fps); %be a bit generous in defining how many frames the task will take
		end
		
		% ===================================================================
		%> @brief showLog
		%>
		%> Generates a table with the randomised stimulus values
		% ===================================================================
		function showLog(obj)
			obj.h = struct();
			build_gui();
			data = [obj.outValues obj.outIndex obj.outMap];
			if isempty(data)
				data = 'No variables!';
			end
			cnames = cell(obj.nVars,1);
			for ii = 1:obj.nVars
				cnames{ii} = obj.nVar(ii).name;
			end
			cnames{end+1} = 'outIndex';
			cnames{end+1} = 'Var1Index';
			cnames{end+1} = 'Var2Index';
			cnames{end+1} = 'Var3Index';
			
			set(obj.h.uitable1,'Data',data)
			set(obj.h.uitable1,'ColumnName',cnames);
			set(obj.h.uitable1,'ColumnWidth',{60});
			set(obj.h.uitable1,'FontName','FixedWidth')
			set(obj.h.uitable1,'RowStriping','on')

			function build_gui()
				obj.h.figure1 = figure( ...
					'Tag', 'sSLog', ...
					'Units', 'normalized', ...
					'Position', [0.1 0.1 0.2 0.5], ...
					'Name', 'stimulusSequence Presentation Order', ...
					'MenuBar', 'none', ...
					'NumberTitle', 'off', ...
					'Color', [0.94 0.94 0.94], ...
					'Resize', 'on');
				obj.h.uitable1 = uitable( ...
					'Parent', obj.h.figure1, ...
					'Tag', 'uitable1', ...
					'Units', 'normalized', ...
					'Position', [0 0 1 0.98], ...
					'FontName', 'Helvetica', ...
					'FontSize', 10, ...
					'BackgroundColor', [1 1 1;0.95 0.95 0.95], ...
					'ColumnEditable', [false,false], ...
					'ColumnFormat', {'char'}, ...
					'ColumnWidth', {'auto'});
				obj.h.uitable2 = uitable( ...
					'Parent', obj.h.figure1, ...
					'Tag', 'uitable1', ...
					'Units', 'normalized', ...
					'Position', [0 0.98 1 0.02], ...
					'FontName', 'Helvetica', ...
					'FontSize', 10, ...
					'BackgroundColor', [1 1 1;0.95 0.95 0.95], ...
					'ColumnEditable', [false,false], ...
					'ColumnFormat', {'char'}, ...
					'ColumnWidth', {'auto'});
			end
		end
		
	end % END STATIC METHODS
	
	%=======================================================================
	methods ( Access = private ) % PRIVATE METHODS
	%=======================================================================

		
	end
	
	%=======================================================================
	methods (Static) %------------------STATIC METHODS
	%=======================================================================
	
		% ===================================================================
		%> @brief loadobj handler
		%>
		%> The problem is we use set.nVar to allow robust setting of
		%> variables, but set.nVar also gets called on loading and will mangle
		%> older saved protocols during load. We need to specify we are loading
		%> and use a conditional in set.nVar to do the right thing.
		% ===================================================================
		function lobj=loadobj(in)
			if ~isa(in,'stimulusSequence') && isstruct(in)
				fprintf('---> Loading stimulusSequence structure...\n');
				lobj = stimulusSequence;
				lobj.isLoading = true;
				fni = fieldnames(in);
				fn = intersect(lobj.loadProperties,fni);
				for i=1:length(fn)
					lobj.(fn{i}) = in.(fn{i});
				end
			elseif isa(in,'stimulusSequence')
				fprintf('---> Loading stimulusSequence object...\n');
				in.currentState = []; %lets strip the old random streams
				in.oldStream = [];
				in.taskStream = [];
				lobj = in;
			end
			lobj.mversion = str2double(regexp(version,'(?<ver>^\d\.\d\d)','match','once'));
			lobj.isLoading = false;
		end
		
	end
	
end