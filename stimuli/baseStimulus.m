% ========================================================================
%> @brief baseStimulus is the superclass for all opticka stimulus objects
%>
%> Superclass providing basic structure for all stimulus classes. This is a dynamic properties
%> descendant, allowing for the temporary run variables used, which get appended "name"Out, i.e.
%> speed is duplicated to a dymanic property called speedOut; it is the dynamic propertiy which is
%> used during runtime, and whose values are converted from definition units like degrees to pixel
%> values that PTB uses.
%>
% ========================================================================
classdef baseStimulus < optickaCore & dynamicprops
	
	properties (Abstract = true, SetAccess = protected)
		%> the stimulus family
		family
	end
	
	properties
		%> X Position in degrees relative to screen center
		xPosition = 0
		%> Y Position in degrees relative to screen center
		yPosition = 0
		%> Size in degrees
		size = 2
		%> Colour as a 0-1 range RGBA
		colour = [0.5 0.5 0.5]
		%> Alpha as a 0-1 range
		alpha = 1
		%> Do we print details to the commandline?
		verbose = false
		%> For moving stimuli do we start "before" our initial position?
		startPosition = 0
		%> speed in degs/s
		speed = 0
		%> angle in degrees
		angle = 0
	end
	
	properties (SetAccess = protected, GetAccess = public)
		%> Our screen rectangle position in PTB format
		dstRect
		%> Our screen rectangle position in PTB format
		mvRect
		%> Our texture pointer for texture-based stimuli
		texture
		%> true or false, whether to draw() this object
		isVisible = true
		%> tick updates +1 on each draw, resets on each update
		tick = 1
	end
	
	properties (SetAccess = protected, GetAccess = public, Transient = true)
		%> handles for the GUI
		handles
	end
	
	properties (Dependent = true, SetAccess = private, GetAccess = public)
		%> What our per-frame motion delta is
		delta
		%> X update which is computed from our speed and angle
		dX
		%> X update which is computed from our speed and angle
		dY
	end
	
	properties (SetAccess = protected, GetAccess = protected)
		%> delta cache
		delta_
		%> dX cache
		dX_
		%> dY cache
		dY_
		%> pixels per degree (calculated in runExperiment)
		ppd = 44
		%> Inter frame interval (calculated in runExperiment)
		ifi = 0.0167
		%> computed X center (calculated in runExperiment)
		xCenter = []
		%> computed Y center (calculated in runExperiment)
		yCenter = []
		%> background colour (calculated in runExperiment)
		backgroundColour = [0.5 0.5 0.5 0]
		%> window to attach to
		win = []
		%>screen to use
		screen = []
		%> Which properties to ignore to clone when making transient copies in
		%> the setup method
		ignorePropertiesBase='name|fullName|family|type|dX|dY|delta|verbose|texture|dstRect|mvRect|isVisible|dateStamp|paths|uuid|tick';
	end
	
	properties (SetAccess = private, GetAccess = private)
		%> properties allowed to be passed on construction
		allowedProperties='name|xPosition|yPosition|size|colour|verbose|alpha|startPosition|angle|speed'
	end
	
	events
		%> triggered when reading from a UI panel,
		readPanelUpdate
	end
	
	%=======================================================================
	methods %------------------PUBLIC METHODS
		%=======================================================================
		
		% ===================================================================
		%> @brief Class constructor
		%>
		%> More detailed description of what the constructor does.
		%>
		%> @param args are passed as a structure of properties which is
		%> parsed.
		%> @return instance of class.
		% ===================================================================
		function obj = baseStimulus(varargin)
			
			if nargin>0
				obj.parseArgs(varargin, obj.allowedProperties);
			end
			
		end
		
		% ===================================================================
		%> @brief colour Get method
		%> Allow 1 (R=G=B) 3 (RGB) or 4 (RGBA) value colour
		% ===================================================================
		function value = get.colour(obj)
			len=length(obj.colour);
			if len == 4
				value = obj.colour;
			elseif len == 3
				value = [obj.colour obj.alpha];
			elseif len == 1
				value = [obj.colour obj.colour obj.colour obj.alpha];
			else
				value = [1 1 1 obj.alpha];				
			end
		end
		
		% ===================================================================
		%> @brief delta Get method
		%> delta is the normalised number of pixels per frame to move a stimulus
		% ===================================================================
		function value = get.delta(obj)
			if isempty(obj.findprop('speedOut'));
				value = (obj.speed * obj.ppd) * obj.ifi;
			else
				value = (obj.speedOut * obj.ppd) * obj.ifi;
			end
		end
		
		% ===================================================================
		%> @brief dX Get method
		%> X position increment for a given delta and angle
		% ===================================================================
		function value = get.dX(obj)
			switch obj.family
				case 'grating'
					if isempty(obj.findprop('motionAngleOut'));
						[value,~]=obj.updatePosition(obj.delta,obj.motionAngle);
					else
						[value,~]=obj.updatePosition(obj.delta,obj.motionAngleOut);
					end
				otherwise
					if isempty(obj.findprop('angleOut'));
						[value,~]=obj.updatePosition(obj.delta,obj.angle);
					else
						[value,~]=obj.updatePosition(obj.delta,obj.angleOut);
					end
			end
		end
		
		% ===================================================================
		%> @brief dY Get method
		%> Y position increment for a given delta and angle
		% ===================================================================
		function value = get.dY(obj)
			switch obj.family
				case 'grating'
					if isempty(obj.findprop('motionAngleOut'));
						[~,value]=obj.updatePosition(obj.delta,obj.motionAngle);
					else
						[~,value]=obj.updatePosition(obj.delta,obj.motionAngleOut);
					end
				otherwise
					if isempty(obj.findprop('angleOut'));
						[~,value]=obj.updatePosition(obj.delta,obj.angle);
					else
						[~,value]=obj.updatePosition(obj.delta,obj.angleOut);
					end
			end
		end
		
		% ===================================================================
		%> @brief Shorthand to set isVisible=true.
		%>
		% ===================================================================
		function show(obj)
			obj.isVisible = true;
		end
		
		% ===================================================================
		%> @brief Shorthand to set isVisible=false.
		%>
		% ===================================================================
		function hide(obj)
			obj.isVisible = false;
		end
		
		% ===================================================================
		%> @brief Run Stimulus in a window to preview
		%>
		% ===================================================================
		function run(obj,benchmark)
			runtime = 2; %seconds to run
			if ~exist('benchmark','var')
				benchmark=false;
			end
			s = screenManager('verbose',false,'blend',true,'screen',0,...
				'bitDepth','8bit','debug',false,...
				'backgroundColour',[0.5 0.5 0.5 0]); %use a temporary screenManager object
			if benchmark
				s.windowed = [];
			else
				s.windowed = [0 0 s.screenVals.width/2 s.screenVals.height/2];
				%s.windowed = CenterRect([0 0 s.screenVals.width/2 s.screenVals.height/2], s.winRect); %middle of screen
			end
			open(s); %open PTB screen
			setup(obj,s); %setup our stimulus object
			draw(obj); %draw stimulus
			drawGrid(s); %draw +-5 degree dot grid
			drawFixationPoint(s); %centre spot
			if benchmark; 
				Screen('DrawText', s.win, 'Benchmark, screen will not update properly, see FPS on command window at end.', 5,5,[0 0 0]);
			else
				Screen('DrawText', s.win, 'Stimulus unanimated for 1 second, animated for 2, then unanimated for a final second...', 5,5,[0 0 0]);
			end
			Screen('Flip',s.win);
			WaitSecs(1);
			if benchmark; b=GetSecs; end
			for i = 1:(s.screenVals.fps*runtime) %should be 2 seconds worth of flips
				draw(obj); %draw stimulus
				drawGrid(s); %draw +-5 degree dot grid
				drawFixationPoint(s); %centre spot
				Screen('DrawingFinished', s.win); %tell PTB/GPU to draw
				animate(obj); %animate stimulus, will be seen on next draw
				if benchmark
					Screen('Flip',s.win,0,2,2);
				else
					Screen('Flip',s.win); %flip the buffer
				end
			end
			if benchmark; bb=GetSecs; end
			WaitSecs(1);
			Screen('Flip',s.win);
			WaitSecs(0.25);
			if benchmark
				fps = (s.screenVals.fps*runtime) / (bb-b);
				fprintf('\n------> SPEED = %g fps\n', fps);
			end
			close(s); %close screen
			clear s fps benchmark runtime b bb i; %clear up a bit
			reset(obj); %reset our stimulus ready for use again
		end
		
		% ===================================================================
		%> @brief make a GUI properties panel for this object
		%>
		% ===================================================================
		function handles = makePanel(obj,parent)
			
			if ~isempty(obj.handles) && isa(obj.handles.root,'uiextras.BoxPanel')
				fprintf('---> Panel already open for %s\n', obj.fullName);
				return
			end
			
			if ~exist('parent','var')
				parent = figure('Tag','gFig',...
					'Name', [obj.fullName 'Properties'], ...
					'MenuBar', 'none', ...
					'NumberTitle', 'off');
			end
			
			handles.parent = parent;
			handles.root = uiextras.BoxPanel('Parent',parent,...
				'Title',obj.fullName,...
				'TitleColor',[0.8 0.79 0.78],...
				'BackgroundColor',[0.83 0.83 0.83]);
			handles.hbox = uiextras.HBox('Parent', handles.root);
			handles.grid1 = uiextras.Grid('Parent', handles.hbox);
			handles.grid2 = uiextras.Grid('Parent', handles.hbox);
			handles.grid3 = uiextras.VButtonBox('Parent',handles.hbox);
			
			idx = {'handles.grid1','handles.grid2','handles.grid3'};
			
			pr = findAttributesandType(obj,'SetAccess','public','notlogical');
			pr = sort(pr);
			lp = ceil(length(pr)/2);
			
			pr2 = findAttributesandType(obj,'SetAccess','public','logical');
			pr2 = sort(pr2);
			lp2 = length(pr2);

			for i = 1:2
				for j = 1:lp
					cur = lp*(i-1)+j;
					if cur <= length(pr);
						val = obj.(pr{cur});
						if ischar(val)
							if isprop(obj,[pr{cur} 'List'])
								if strcmp(obj.([pr{cur} 'List']),'filerequestor')
									val = regexprep(val,'\s+',' ');
									handles.([pr{cur} '_char']) = uicontrol('Style','edit',...
										'Parent',eval(idx{i}),...
										'Tag',['panel' pr{cur}],...
										'String',val);
								else
									txt=obj.([pr{cur} 'List']);
									fidx = strcmpi(txt,obj.(pr{cur}));
									fidx = find(fidx > 0);
									handles.([pr{cur} '_list']) = uicontrol('Style','popupmenu',...
										'Parent',eval(idx{i}),...
										'Tag',['panel' pr{cur} 'List'],...
										'String',txt,...
										'Value',fidx);
								end
							else
								val = regexprep(val,'\s+',' ');
								handles.([pr{cur} '_char']) = uicontrol('Style','edit',...
									'Parent',eval(idx{i}),...
									'Tag',['panel' pr{cur}],...
									'String',val);
							end
						elseif isnumeric(val)
							val = num2str(val);
							val = regexprep(val,'\s+',' ');
							handles.([pr{cur} '_num']) = uicontrol('Style','edit',...
								'Parent',eval(idx{i}),...
								'Tag',['panel' pr{cur}],...
								'String',val,...
								'FontName','Menlo');
						else
							uiextras.Empty('Parent',eval(idx{i}));
						end
					else
						uiextras.Empty('Parent',eval(idx{i}));
					end
				end
				
				for j = 1:lp
					cur = lp*(i-1)+j;
					if cur <= length(pr);
						if isprop(obj,[pr{cur} 'List'])
							if strcmp(obj.([pr{cur} 'List']),'filerequestor')
								uicontrol('Style','pushbutton',...
								'Parent',eval(idx{i}),...
								'HorizontalAlignment','left',...
								'String','Select file...',...
								'FontName','Georgia');
							else
								uicontrol('Style','text',...
								'Parent',eval(idx{i}),...
								'HorizontalAlignment','left',...
								'String',pr{cur},...
								'FontName','Georgia');
							end
						else
							uicontrol('Style','text',...
							'Parent',eval(idx{i}),...
							'HorizontalAlignment','left',...
							'String',pr{cur},...
							'FontName','Georgia');
						end
					else
						uiextras.Empty('Parent',eval(idx{i}));
					end
				end
				eval([idx{i} '.ColumnSizes = [-1,-1];']);
			end
			for j = 1:lp2
				val = obj.(pr2{j});
				if j < length(pr2)
					handles.([pr2{j} '_bool']) = uicontrol('Style','checkbox',...
						'Parent',eval(idx{end}),...
						'Tag',['panel' pr2{j}],...
						'String',pr2{j},...
						'Value',val);
				end
			end
			handles.readButton = uicontrol('Style','pushbutton',...
				'Parent',eval(idx{end}),...
				'Tag','readButton',...
				'Callback',@obj.readPanel,...
				'String','Update');
			obj.handles = handles;
			
		end
		
		% ===================================================================
		%> @brief read values from a GUI properties panel for this object
		%>
		% ===================================================================
		function readPanel(obj,varargin)
			if isempty(obj.handles) || ~isa(obj.handles.root,'uiextras.BoxPanel')
				return
			end
				
			pList = findAttributes(obj,'SetAccess','public'); %our public properties
			handleList = fieldnames(obj.handles); %the handle name list
			handleListMod = regexprep(handleList,'_.+$',''); %we remove the suffix so names are equivalent
			
			outList = intersect(pList,handleListMod);
			
			for i=1:length(outList)
				hidx = strcmpi(handleListMod,outList{i});
				handleNameOut = handleListMod{hidx};
				handleName = handleList{hidx};
				handleType = regexprep(handleName,'^.+_','');
				while iscell(handleType);handleType=handleType{1};end
				switch handleType
					case 'list'
						str = get(obj.handles.(handleName),'String');
						v = get(obj.handles.(handleName),'Value');
						obj.(handleNameOut) = str{v};
					case 'bool'
						obj.(handleNameOut) = logical(get(obj.handles.(handleName),'Value'));
					case 'num'
						obj.(handleNameOut) = str2num(get(obj.handles.(handleName),'String')); %#ok<ST2NM>
					case 'char'
						obj.(handleNameOut) = get(obj.handles.(handleName),'String');
				end
			end
			notify(obj,'readPanelUpdate');
		end
			
		% ===================================================================
		%> @brief read values from a GUI properties panel for this object
		%>
		% ===================================================================
		function showPanel(obj)
			if isempty(obj.handles)
				return
			end
			set(obj.handles.root,'Enable','on');
			set(obj.handles.root,'Visible','on');
		end
		
		% ===================================================================
		%> @brief read values from a GUI properties panel for this object
		%>
		% ===================================================================
		function hidePanel(obj)
			if isempty(obj.handles)
				return
			end
			set(obj.handles.root,'Enable','off');
			set(obj.handles.root,'Visible','off');
		end
		
		% ===================================================================
		%> @brief read values from a GUI properties panel for this object
		%>
		% ===================================================================
		function closePanel(obj)
			if isempty(obj.handles)
				return
			end
			if ~isempty(obj.handles.root)
				readPanel(obj);
				delete(obj.handles.root);
			end
			obj.handles = [];
		end
		
		
	end %---END PUBLIC METHODS---%
	
	%=======================================================================
	methods (Abstract)%------------------ABSTRACT METHODS
	%=======================================================================
		%> initialise the stimulus
		out = setup(runObject)
		%> update the stimulus
		out = update(runObject)
		%>draw to the screen buffer
		out = draw(runObject)
		%> animate the settings
		out = animate(runObject)
		%> reset to default values
		out = reset(runObject)
	end %---END ABSTRACT METHODS---%
	
	%=======================================================================
	methods ( Static ) %----------STATIC METHODS
	%=======================================================================
		
		% ===================================================================
		%> @brief degrees2radians
		%>
		% ===================================================================
		function r = d2r(degrees)
			r=degrees*(pi/180);
		end
		
		% ===================================================================
		%> @brief radians2degrees
		%>
		% ===================================================================
		function degrees=r2d(r)
			degrees=r*(180/pi);
		end
		
		% ===================================================================
		%> @brief findDistance in X and Y coordinates
		%>
		% ===================================================================
		function distance=findDistance(x1,y1,x2,y2)
			dx = x2 - x1;
			dy = y2 - y1;
			distance=sqrt(dx^2 + dy^2);
		end
		
		% ===================================================================
		%> @brief updatePosition returns dX and dY given an angle and delta
		%>
		% ===================================================================
		function [dX dY] = updatePosition(delta,angle)
			dX = delta .* cos(baseStimulus.d2r(angle));
			dY = delta .* sin(baseStimulus.d2r(angle));
			%if abs(dX) < 1e-6; dX = 0; end
			%if abs(dY) < 1e-6; dY = 0; end
		end
		
	end%---END STATIC METHODS---%
	
	%=======================================================================
	methods ( Access = protected ) %-------PRIVATE (protected) METHODS-----%
	%=======================================================================
		
		
		% ===================================================================
		%> @brief setRect
		%>  setRect makes the PsychRect based on the texture and screen values
		% ===================================================================
		function setRect(obj)
			if isempty(obj.findprop('angleOut'));
				[dx, dy]=pol2cart(obj.d2r(obj.angle),obj.startPosition);
			else
				[dx, dy]=pol2cart(obj.d2r(obj.angleOut),obj.startPosition);
			end
			obj.dstRect=Screen('Rect',obj.texture);
			obj.dstRect=CenterRectOnPointd(obj.dstRect,obj.xCenter,obj.yCenter);
			if isempty(obj.findprop('xPositionOut'));
				obj.dstRect=OffsetRect(obj.dstRect,obj.xPosition*obj.ppd,obj.yPosition*obj.ppd);
			else
				obj.dstRect=OffsetRect(obj.dstRect,obj.xPositionOut+(dx*obj.ppd),obj.yPositionOut+(dy*obj.ppd));
			end
			obj.mvRect=obj.dstRect;
			obj.setAnimationDelta();
		end
		
		% ===================================================================
		%> @brief setAnimationDelta
		%> setAnimationDelta for performance we can't use get methods for dX dY and
		%> delta during animation, so we have to cache these properties to private copies so that
		%> when we call the animate method, it uses the cached versions not the
		%> public versions. This method simply copies the properties to their cached
		%> equivalents.
		% ===================================================================
		function setAnimationDelta(obj)
			obj.delta_ = obj.delta;
			obj.dX_ = obj.dX;
			obj.dY_ = obj.dY;
		end
		
		% ===================================================================
		%> @brief compute xTmp and yTmp
		%>
		% ===================================================================
		function computePosition(obj)
			if isempty(obj.findprop('angleOut'));
				[dx, dy]=pol2cart(obj.d2r(obj.angle),obj.startPosition);
			else
				[dx, dy]=pol2cart(obj.d2r(obj.angleOut),obj.startPositionOut);
			end
			obj.xTmp = obj.xPositionOut + (dx * obj.ppd);
			obj.yTmp = obj.yPositionOut + (dy * obj.ppd);
		end
		
		% ===================================================================
		%> @brief Converts properties to a structure
		%>
		%>
		%> @param obj this instance object
		%> @param tmp is whether to use the temporary or permanent properties
		%> @return out the structure
		% ===================================================================
		function out=toStructure(obj,tmp)
			if ~exist('tmp','var')
				tmp = 0; %copy real properties, not temporary ones
			end
			fn = fieldnames(obj);
			for j=1:length(fn)
				if tmp == 0
					out.(fn{j}) = obj.(fn{j});
				else
					out.(fn{j}) = obj.([fn{j} 'Out']);
				end
			end
		end
		
		% ===================================================================
		%> @brief Finds and removes transient properties
		%>
		%> @param obj
		%> @return
		% ===================================================================
		function removeTmpProperties(obj)
			fn=fieldnames(obj);
			for i=1:length(fn)
				if ~isempty(regexp(fn{i},'Out$','once'))
					delete(obj.findprop(fn{i}));
				end
			end
		end
		
	end%---END PRIVATE METHODS---%
end