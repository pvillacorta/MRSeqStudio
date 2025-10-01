function mat2nifti(filename)
% Convert phantom .mat data to NIfTI for multiple keys

if nargin < 1 || isempty(filename)
	error('Usage: mat2nifti("phantom_filename")');
end

addpath(".");

cd(filename);

dx = 0.5e-3; dy = dx; dz = dx;
margin = 5e-3;

keys = ["T1", "T2", "PD", "dw"];


for i = 1:numel(keys)
	key = keys(i);

	vq = scatterGrid(filename, key, dx, dy, dz, margin);

	% Write compressed NIfTI; filename will be key.nii.gz in the phantom folder
	% result_basename = fullfile(out_dir, key);
	result_basename = key;
	niftiwrite(vq, result_basename, "Compressed", true);
	info = niftiinfo(result_basename);

	info.PixelDimensions = [dx dy dz] * 1e3;
	info.ImageSize = [size(vq, 1) size(vq, 2) size(vq, 3)];
	info.SpaceUnits = "Millimeter";

	niftiwrite(vq, result_basename, info, "Compressed", true);
end

cd("..");

end