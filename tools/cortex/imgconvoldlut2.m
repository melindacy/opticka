%imgconvoldlut2
%B Jagadeesh 6/30/98
%7/2/98 Change (from imgconvoldlut) so that it does looping through files in here. 
%Convert a group of images in imgdirin to cortex format. Use
%a predetermined lookup table. imgdirin and imgdirout must be preset. 
%as well as a file, as lutname, from which to load the lut (with name from c:\matlab\). 

%Variables to check/change for each run.
lutfile='ctximg-mat\1mnalln-mat-lut'
imgdirin='imgin'
imgdirout='imgout'
threelettercode='bbb';startindex=100;
basedir='c:\matlab\';
offset=128;

%Get list of images from directory
imglst=make_file_list(strcat(basedir,imgdirin,'\*.tif'));
imglst2=make_file_list(strcat(basedir,imgdirin,'\*.jpg'));
imglst=strvcat(imglst,imglst2);
imglst=sortrows(imglst);

imgfailed=[];imgsuccess=[];

%Number of images, and the characters in the maximum filename
[nimgs,nchars]=size(imglst);

%If filenames aren't DOS compatible, rename based on index of three letter, 
%number, starting with 100. 
if nchars>12
   disp('files need to be renamed');
   namestart = threelettercode
   ndstart = startindex 
else
   namestart='no';
   ndstart=0;
end

%Load in the file with the lookup table, saved in matlab format
load([basedir,lutfile]);
maptoapply=imgAllMap;
clear imgAll;
clear imgAllInd;

%Display starting conversion
disp(' ');disp(' ');disp(' ');
disp('LUT Loaded from file');
disp('Start converting images');
disp(' ');disp(' ');disp(' ');

for ii=1:nimgs
   %Load the image file
   imgtoload=strcat([basedir,imgdirin,'\'],imglst(ii,:));
   imgrgb=imread(imgtoload);
   
   %Set the output file name
   if strcmp(namestart,'no');
      imgout=strcat([basedir,imgdirout,'\'],imglst(ii,1:nchars-4));
   else
      imgout=strcat([basedir,imgdirout,'\'],namestart,sprintf('%3.0f',ndstart+ii-1));
   end
   
   %Index the image
   [imgInd]=rgb2ind(imgrgb,maptoapply,'no dither');
   
   %Draw original & indexed image
   subplot(1,2,1), subimage(imgrgb)
   subplot(1,2,2), subimage(imgInd,maptoapply)
   drawnow
   
   %Display image name & output image name on screen. 
   temp=strcat(sprintf('input %s output %s',imglst(ii,:),[imgout,'.ctx']));
   disp(temp);disp(' ');
   
   %Write ctx file, version that writes lookup table for first image
   if ii==1
   	worked=im2cortbj(imgInd, maptoapply, imgout, offset,1);
   end
   
   %Write ctx file, version that doesn't write lookup table
   if ii>1
   	worked=im2cortbj(imgInd, maptoapply, imgout, offset,0);
	end
   
   %Check value returned from im2cort and make list of
   %successful images and failed iamges. 
   if worked ~=1
      imgfailed=strvcat(imgfailed,imglst(ii,:));
   else
      imgsuccess=strvcat(imgsuccess,imglst(ii,:));
   end
end