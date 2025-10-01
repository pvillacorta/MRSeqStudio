function A = scatterGrid(filename, key, dx, dy, dz, margin, dmax)
    arguments
        filename string
        key string
        dx double = 1e-3
        dy double = 1e-3
        dz double = 1e-3
        margin double = 5e-3
        dmax double = 3*dx
    end
    ph = load(filename);

    if key == "T1"
        value = ph.T1;
    elseif key == "T2"
        value = ph.T2;
    elseif key == "PD"
        value = ph.PD;
    elseif key == "dw"
        value = ph.dw;
    end

    if all(ph.z == ph.z(1))
        x = ph.x;
        y = ph.y;

        F = scatteredInterpolant(x, y, value, 'linear', 'none');

        x_max = max(x) + margin;
        y_max = max(y) + margin;
    
        x_min = min(x) - margin;
        y_min = min(y) - margin;
    
        nx = (x_max - x_min) / dx;
        ny = (y_max - y_min) / dy;
    
        xg = linspace(x_min, x_max, nx);
        yg = linspace(y_min, y_max, ny);
    
        [xq, yq] = meshgrid(xg, yg);
    
        vq = F(xq, yq);

        queryPoints = [xq(:), yq(:)];
        dataPoints =  [x(:),  y(:)];

        [idx, dist] = knnsearch(dataPoints, queryPoints);
        mask = reshape(dist <= dmax, size(xq));
        vq(~mask) = 0;

        vq = repmat(vq, [1, 1, 2]);
    else
        x = ph.x;
        y = ph.y;
        z = ph.z;

        F = scatteredInterpolant(x, y, z, value, 'linear', 'none');

        x_max = max(x) + margin;
        y_max = max(y) + margin;
        z_max = max(z) + margin;

        x_min = min(x) - margin;
        y_min = min(y) - margin;
        z_min = min(z) - margin;

        nx = (x_max - x_min) / dx;
        ny = (y_max - y_min) / dy;
        nz = (z_max - z_min) / dz;
    
        xg = linspace(x_min, x_max, nx);
        yg = linspace(y_min, y_max, ny);
        zg = linspace(z_min, z_max, nz);
    
        [xq, yq, zq] = meshgrid(xg, yg, zg);
    
        vq = F(xq, yq, zq);

        queryPoints = [xq(:), yq(:), zq(:)];
        dataPoints =  [x(:),  y(:),  z(:)];

        [idx, dist] = knnsearch(dataPoints, queryPoints);
        mask = reshape(dist <= dmax, size(xq));
        vq(~mask) = 0;
    end
    vq(isnan(vq)) = 0;
    vq = int16(floor(vq * 1e3));
    A = permute(vq, [2,1,3]);
end