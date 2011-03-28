% ========================================================================
%> @brief single bar stimulus, inherits from baseStimulus
%> SPOTSTIMULUS single bar stimulus, inherits from baseStimulus
%>   The current properties are:
% ========================================================================
classdef rfMapper < barStimulus
	
	properties %--------------------PUBLIC PROPERTIES----------%
		%> normally should be left at 1 (1 is added to this number so doublebuffering is enabled)
		doubleBuffer = 1
		%> multisampling sent to the graphics card, try values []=disabled, 4, 8 and 16
		antiAlias = 4
		%> use OpenGL blending mode 1 = yes | 0 = no
		blend = true
		%> GL_ONE %src mode
		srcMode = 'GL_ONE'
		%> GL_ONE % dst mode
		dstMode = 'GL_ZERO'
	end
	
	properties (SetAccess = private, GetAccess = public)
		winRect = []
		buttons = []
		rchar = ''
		xClick = 0
		yClick = 0
		xyDots = [0;0]
		comment = ''
		showClicks = 0
		stimulus = 'bar'
	end
	
	properties (SetAccess = private, GetAccess = private)
		gratingTexture
		sf
		tf
		phase
		colourIndex = 1
		bgcolourIndex = 2
		colourList = {[1 1 1];[0 0 0];[1 0 0];[0 1 0];[0 0 1];[1 1 0];[1 0 1];[0 1 1];[.5 .5 .5]}
		textureIndex = 1
		textureList = {'simple','random','randomColour','randomN','randomBW'};
		allowedProperties='^(type|screen|blend|antiAlias)$'
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
		%> @return instance of the class.
		% ===================================================================
		function obj = rfMapper(args)
			%Initialise for superclass, stops a noargs error
			if nargin == 0
				args.family = 'rfmapper';
			end
			obj=obj@barStimulus(args); %we call the superclass constructor first
			if nargin>0 && isstruct(args)
				fnames = fieldnames(args); %find our argument names
				for i=1:length(fnames);
					if regexp(fnames{i},obj.allowedProperties) %only set if allowed property
						obj.salutation(fnames{i},'Configuring setting in rfMapper constructor');
						obj.(fnames{i})=args.(fnames{i}); %we set up the properies from the arguments as a structure
					end
				end
			end
			obj.backgroundColour = [ 0 0 0 0];
			obj.family = 'rfmapper';
			obj.salutation('constructor','rfMapper initialisation complete');
		end
		
		% ===================================================================
		%> @brief
		%>
		% ===================================================================
		function run(obj,rE)
			obj.screen = rE.screen;
			try
				Screen('Preference', 'SkipSyncTests', 2);
				Screen('Preference', 'VisualDebugLevel', 0);
				Screen('Preference', 'Verbosity', 2);
				Screen('Preference', 'SuppressAllWarnings', 0);
				PsychImaging('PrepareConfiguration');
				PsychImaging('AddTask', 'General', 'FloatingPoint32BitIfPossible');
				PsychImaging('AddTask', 'General', 'NormalizedHighresColorRange');
				[obj.win, obj.winRect] = PsychImaging('OpenWindow', obj.screen, obj.backgroundColour,[], [], obj.doubleBuffer+1,[],obj.antiAlias);
				
				[obj.xCenter, obj.yCenter] = RectCenter(obj.winRect);
				Priority(MaxPriority(obj.win)); %bump our priority to maximum allowed
				
				obj.setup(rE);
				AssertGLSL;
				
				% Enable alpha blending.
				if obj.blend==1
					Screen('BlendFunction', obj.win, obj.srcMode, obj.dstMode);
				end
				
				obj.buttons = [0 0 0]; % When the user clicks the mouse, 'buttons' becomes nonzero.
				mX = 0; % The x-coordinate of the mouse cursor
				mY = 0; % The y-coordinate of the mouse cursor
				xOut = 0;
				yOut = 0;
				obj.rchar='';
				FlushEvents;
				HideCursor;
				ListenChar(2);
				
				while isempty(regexpi(obj.rchar,'^esc'))
					
					%draw background
					Screen('FillRect',obj.win,obj.backgroundColour,[]);
					
					%draw text
					t=sprintf('Buttons: %i\t',obj.buttons);
					t=[t sprintf(' | X = %2.3g| Y = %2.3g',xOut,yOut)];
					if ischar(obj.rchar);t=[t sprintf('| Char: %s',obj.rchar)];end
					t=[t sprintf('Scale = %2.2g',obj.scale)];
					Screen('DrawText', obj.win, t, 0, 0, [1 1 0]);
					
					%draw central spot
					sColour = obj.backgroundColour./2;
					if max(sColour)==0;sColour=[0.5 0.5 0.5 1];end
					Screen('gluDisk',obj.win,sColour,obj.xCenter,obj.yCenter,2);
					
					%draw clicked points
					if obj.showClicks == 1
						Screen('DrawDots',obj.win,obj.xyDots,2,sColour,[obj.xCenter obj.yCenter],1);
					end
					
					% Draw the sprite at the new location.
					if obj.isVisible == true
						switch obj.stimulus
							case 'bar'
								Screen('DrawTexture', obj.win, obj.texture, [], obj.dstRect, obj.angleOut,[],obj.alpha);
							case 'grating'

						end
					end
					
					Screen('DrawingFinished', obj.win); % Tell PTB that no further drawing commands will follow before Screen('Flip')
					
					[mX, mY, obj.buttons] = GetMouse(obj.screen);
					xOut = (mX - obj.xCenter)/obj.ppd;
					yOut = (mY - obj.yCenter)/obj.ppd;
					if obj.buttons(2) == 1
						obj.xClick = [obj.xClick xOut];
						obj.yClick = [obj.yClick yOut];
						obj.xyDots = vertcat((obj.xClick.*obj.ppd),(obj.yClick*obj.ppd));
					end
					obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
					[keyIsDown, ~, keyCode] = KbCheck;
					if keyIsDown == 1
						obj.rchar = KbName(keyCode);
						if iscell(obj.rchar);obj.rchar=obj.rchar{1};end
						switch obj.rchar
							case 'l' %increase length
								switch obj.stimulus
									case 'bar'
										obj.dstRect=ScaleRect(obj.dstRect,1,1.05);
										obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
								end
							case 'k' %decrease length
								switch obj.stimulus
									case 'bar'
										obj.dstRect=ScaleRect(obj.dstRect,1,0.95);
										obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
								end
							case 'j' %increase width
								switch obj.stimulus
									case 'bar'
										obj.dstRect=ScaleRect(obj.dstRect,1.05,1);
										obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
								end
							case 'h' %decrease width
								switch obj.stimulus
									case 'bar'
										obj.dstRect=ScaleRect(obj.dstRect,0.95,1);
										obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
								end
							case 'm' %increase size
								switch obj.stimulus
									case 'bar'
										[w,h]=RectSize(obj.dstRect);
										if w ~= h
											m = max(w,h);
											obj.dstRect = SetRect(0,0,m,m);
											
										end
										obj.dstRect=ScaleRect(obj.dstRect,1.05,1.05);
										obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
								end
							case 'n' %decrease size
								switch obj.stimulus
									case 'bar'
										[w,h]=RectSize(obj.dstRect);
										if w ~= h
											m = max(w,h);
											obj.dstRect =  SetRect(0,0,m,m);
										end
										obj.dstRect=ScaleRect(obj.dstRect,0.95,0.95);
										obj.dstRect=CenterRectOnPointd(obj.dstRect,mX,mY);
								end
							case 'g'
								switch obj.stimulus
									case 'bar'
										obj.stimulus = 'grating';
									case 'grating'
										obj.stimulus = 'bar';
								end
							case 'v'
								if obj.isVisible == true
									obj.hide;
								else
									obj.show;
								end
							case {'LeftArrow','left'}
								obj.angleOut = obj.angleOut-5;
							case {'RightArrow','right'}
								obj.angleOut = obj.angleOut+5;
							case {'UpArrow','up'}
								obj.alpha = obj.alpha * 1.1;
								if obj.alpha > 1;obj.alpha = 1;end
							case {'DownArrow','down'}
								obj.alpha = obj.alpha * 0.9;
								if obj.alpha < 0;obj.alpha = 0;end
							case ',<'
								if max(obj.backgroundColour)>0.1
									obj.backgroundColour = obj.backgroundColour .* 0.9;
									obj.backgroundColour(obj.backgroundColour<0) = 0;
								end
							case '.>'
								obj.backgroundColour = obj.backgroundColour .* 1.1;
								obj.backgroundColour(obj.backgroundColour>1) = 1;
							case '1!'
								obj.colourIndex = obj.colourIndex+1;
								obj.setColours;
								WaitSecs(0.03);
								obj.regenerate;
							case '2@'
								obj.bgcolourIndex = obj.bgcolourIndex+1;
								obj.setColours;
								WaitSecs(0.02);
								obj.regenerate;
							case '3#'
								switch obj.stimulus
									case 'bar'
										obj.scale = obj.scale * 1.1;
										if obj.scale > 8;obj.scale = 8;end
								end
							case '4$'
								switch obj.stimulus
									case 'bar'
										obj.scale = obj.scale * 0.9;
										if obj.scale <1;obj.scale = 1;end
								end
							case 'space'
								switch obj.stimulus
									case 'bar'
										obj.textureIndex = obj.textureIndex + 1;
										obj.barWidth = obj.dstRect(3)/obj.ppd;
										obj.barLength = obj.dstRect(4)/obj.ppd;
										obj.type = obj.textureList{obj.textureIndex};
										WaitSecs(0.1);
										obj.regenerate;
									case 'grating'
										
								end
							case {';:',';'}
								obj.showClicks = ~obj.showClicks;
								WaitSecs(0.1);
							case {'''"',''''}
								obj.xClick = 0;
								obj.yClick = 0;
								obj.xyDots = vertcat((obj.xClick.*obj.ppd),(obj.yClick*obj.ppd));
						end
					end
					FlushEvents('keyDown');
					Screen('Flip', obj.win);
				end
				
				obj.win=[];
				Priority(0);
				ListenChar(0)
				ShowCursor;
				Screen('CloseAll');
				
			catch ME
				obj.win=[];
				Priority(0);
				ListenChar(0)
				% If there is an error in our try block, let's
				% return the user to the familiar MATLAB prompt.
				ShowCursor;
				Screen('CloseAll');
				psychrethrow(psychlasterror);
				rethrow ME
			end
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function set.colourIndex(obj,value)
			obj.colourIndex = value;
			if obj.colourIndex > length(obj.colourList)
				obj.colourIndex = 1;
			end
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function set.bgcolourIndex(obj,value)
			obj.bgcolourIndex = value;
			if obj.bgcolourIndex > length(obj.colourList)
				obj.bgcolourIndex = 1;
			end
		end
		
		% ===================================================================
		%> @brief
		%>
		%> @param
		%> @return
		% ===================================================================
		function set.textureIndex(obj,value)
			obj.textureIndex = value;
			if obj.textureIndex > length(obj.textureList)
				obj.textureIndex = 1;
			end
		end
	end
	
	%=======================================================================
	methods ( Access = private ) %-------PRIVATE METHODS-----%
		%=======================================================================
		% ===================================================================
		%> @brief setColours
		%>  sets the colours based on the current index
		% ===================================================================
		function setColours(obj)
			obj.colour = obj.colourList{obj.colourIndex};
			obj.backgroundColour = obj.colourList{obj.bgcolourIndex};
		end
		
		% ===================================================================
		%> @brief regenerate
		%>  regenerates the texture
		% ===================================================================
		function regenerate(obj)
			Screen('Close',obj.texture);
			obj.constructMatrix(obj.ppd) %make our matrix
			obj.texture=Screen('MakeTexture',obj.win,obj.matrix,1,[],2);
		end
	end
end