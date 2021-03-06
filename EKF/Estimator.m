function [posEst,linVelEst,oriEst,windEst,driftEst,...
          posVar,linVelVar,oriVar,windVar,driftVar,estState] = ...
    Estimator_mine(estState,actuate,sense,tm,estConst)
% [posEst,linVelEst,oriEst,windEst,driftEst,...
%    posVar,linVelVar,oriVar,windVar,driftVar,estState] = 
% Estimator(estState,actuate,sense,tm,estConst)
%
% The estimator.
%
% The function is initialized for tm == 0, otherwise the estimator does an
% iteration step (compute estimates for the time step k).
%
% Inputs:
%   estState        previous estimator state (time step k-1)
%                   May be defined by the user (for example as a struct).
%   actuate         control input u(k-1), [1x2]-vector
%                   actuate(1): u_t, thrust command
%                   actuate(2): u_r, rudder command
%   sense           sensor measurements z(k), [1x5]-vector, INF entry if no
%                   measurement
%                   sense(1): z_a, distance measurement a
%                   sense(2): z_b, distance measurement b
%                   sense(3): z_c, distance measurement c
%                   sense(4): z_g, gyro measurement
%                   sense(5): z_n, compass measurement
%   tm              time t_k, scalar
%                   If tm==0 initialization, otherwise estimator
%                   iteration step.
%   estConst        estimator constants (as in EstimatorConst.m)
%
% Outputs:
%   posEst          position estimate (time step k), [1x2]-vector
%                   posEst(1): p_x position estimate
%                   posEst(2): p_y position estimate
%   linVelEst       velocity estimate (time step k), [1x2]-vector
%                   linVelEst(1): s_x velocity estimate
%                   linVelEst(2): s_y velocity estimate
%   oriEst          orientation estimate (time step k), scalar
%   windEst         wind direction estimate (time step k), scalar
%   driftEst        estimate of the gyro drift b (time step k), scalar
%   posVar          variance of position estimate (time step k), [1x2]-vector
%                   posVar(1): x position variance
%                   posVar(2): y position variance
%   linVelVar       variance of velocity estimate (time step k), [1x2]-vector
%                   linVelVar(1): x velocity variance
%                   linVelVar(2): y velocity variance
%   oriVar          variance of orientation estimate (time step k), scalar
%   windVar         variance of wind direction estimate(time step k), scalar
%   driftVar        variance of gyro drift estimate (time step k), scalar
%   estState        current estimator state (time step k)
%                   Will be input to this function at the next call.
%
%
% Class:
% Recursive Estimation
% Spring 2021
% Programming Exercise 1
%
% --
% ETH Zurich
% Institute for Dynamic Systems and Control
% Raffaello D'Andrea, Matthias Hofer, Carlo Sferrazza
% hofermat@ethz.ch
% csferrazza@ethz.ch

%% Initialization
if (tm == 0)
    % Do the initialization of your estimator here!
    
    % initial state mean
    posEst = [0, 0]; % 1x2 matrix
    linVelEst = [0, 0]; % 1x2 matrix
    oriEst = 0; % 1x1 matrix
    windEst = 0; % 1x1 matrix
    driftEst = 0; % 1x1 matrix
    
    % initial state variance
    posVar = pi/4 * estConst.StartRadiusBound^4 * [1,1]; % 1x2 matrix
    linVelVar = [0, 0]; % 1x2 matrix
    oriVar = estConst.RotationStartBound^2 / 3; % 1x1 matrix
    windVar = estConst.WindAngleStartBound^2 / 3; % 1x1 matrix
    driftVar = estConst.GyroDriftStartBound; % 1x1 matrix
    
    % estimator variance init (initial posterior variance)
    estState.Pm = diag([posVar, linVelVar, oriVar, windVar, driftVar]);
    % estimator state
    estState.xm = [posEst, linVelEst, oriEst, windEst, driftEst];
    % time of last update
    estState.tm = tm;
    return;
end


%% Estimator iteration.
% get time since last estimator update
dt = tm - estState.tm;
estState.tm = tm; % update measurement update time

% the order of state variable here is:
% x = [px, py, sx, sy, phi, rho, b]'

u_t = actuate(1);
u_r = actuate(2);

%% prior update

% solve xp[k]
x0 = estState.xm';
x0 = reshape(x0, [7,1]);
tspan = linspace(tm-dt, tm, 50);
[xt, x] = ode45(@(t, x) dynamics_mean(t, x, estConst, u_t, u_r), tspan, x0);
xp = x(end, :)';

% solve Pp[k]
P0 = estState.Pm;
[Pt, P] = ode45(@(t, P) dynamics_variance(t, P, xt, x, estConst, u_t, u_r), tspan, P0(:));
Pp = P(end, :);
Pp = reshape(Pp, [7,7]);


%% measurement update
px = xp(1);
py = xp(2);
phi = xp(5);
b = xp(7);

x_a = estConst.pos_radioA(1);
y_a = estConst.pos_radioA(2);
x_b = estConst.pos_radioB(1);
y_b = estConst.pos_radioB(2);
x_c = estConst.pos_radioC(1);
y_c = estConst.pos_radioC(2);

H = zeros(5,7);
H(1,1) = (px - x_a) / sqrt( (px-x_a)^2 + (py-y_a)^2 );
H(1,2) = (py - y_a) / sqrt( (px-x_a)^2 + (py-y_a)^2 );
H(2,1) = (px - x_b) / sqrt( (px-x_b)^2 + (py-y_b)^2 );
H(2,2) = (py - y_b) / sqrt( (px-x_b)^2 + (py-y_b)^2 );
H(3,1) = (px - x_c) / sqrt( (px-x_c)^2 + (py-y_c)^2 );
H(3,2) = (py - y_c) / sqrt( (px-x_c)^2 + (py-y_c)^2 );
H(4,5) = 1;
H(4,7) = 1;
H(5,5) = 1;
M = eye(5);
R = diag([estConst.DistNoiseA, estConst.DistNoiseB, estConst.DistNoiseC, estConst.GyroNoise, estConst.CompassNoise]);
z = sense';
h = [sqrt( (px-x_a)^2 + (py-y_a)^2 );...
    sqrt( (px-x_b)^2 + (py-y_b)^2 );...
    sqrt( (px-x_c)^2 + (py-y_c)^2 );...
    phi + b;...
    phi];

if sense(3) == inf
    H(3,:) = [];
    M = eye(4);
    R = diag([estConst.DistNoiseA, estConst.DistNoiseB, estConst.GyroNoise, estConst.CompassNoise]);
    z(3) = [];
    h(3) = [];
end

K = Pp * H' / (H * Pp * H' + M * R * M');
xm = xp + K * (z - h);
Pm = (eye(7) - K*H) * Pp;

estState.xm = xm';
estState.Pm = Pm;

% Get resulting estimates and variances
% Output quantities

posEst = xm(1:2);
linVelEst = xm(3:4);
oriEst = xm(5);
windEst = xm(6);
driftEst = xm(7);

posVar = [Pm(1,1), Pm(2,2)];
linVelVar = [Pm(3,3), Pm(4,4)];
oriVar = Pm(5,5);
windVar = Pm(6,6);
driftVar = Pm(7,7);

end



%% 
function dxdt = dynamics_mean(t, x, estConst, u_t, u_r)
sx = x(3);
sy = x(4);
phi = x(5);
rho = x(6);

Cdh = estConst.dragCoefficientHydr;
Cda = estConst.dragCoefficientAir;
Cr = estConst.rudderCoefficient;
Cw = estConst.windVel;

dxdt = zeros(7,1);
dxdt(1) = sx;
dxdt(2) = sy;
dxdt(3) = cos(phi)*(tanh(u_t) - Cdh*(sx^2+sy^2)) - Cda*(sx-Cw*cos(rho)) *...
    sqrt( (sx-Cw*cos(rho))^2 + (sy-Cw*sin(rho))^2 );
dxdt(4) = sin(phi)*(tanh(u_t) - Cdh*(sx^2+sy^2)) - Cda*(sy-Cw*sin(rho)) *...
    sqrt( (sx-Cw*cos(rho))^2 + (sy-Cw*sin(rho))^2 );
dxdt(5) = Cr * u_r;
end


function dPdt = dynamics_variance(t, P, xt, x, estConst, u_t, u_r)

sx = interp1(xt, x(:,3), t);
sy = interp1(xt, x(:,4), t);
phi = interp1(xt, x(:,5), t);
rho = interp1(xt, x(:,6), t);

Cdh = estConst.dragCoefficientHydr;
Cda = estConst.dragCoefficientAir;
Cr = estConst.rudderCoefficient;
Cw = estConst.windVel;

A = zeros(7);
squareroot = sqrt( (sx-Cw*cos(rho))^2 + (sy-Cw*sin(rho))^2 );
A(1,3) = 1;
A(2,4) = 1;
A(3,3) = cos(phi) * (-2 * Cdh * sx) - Cda * squareroot - Cda * (sx-Cw*cos(rho))^2 / squareroot;
A(3,4) = cos(phi) * (-2 * Cdh * sy) - Cda * (sx-Cw*cos(rho))*(sy-Cw*sin(rho)) / squareroot;
A(3,5) = -sin(phi) * (tanh(u_t) - Cdh*(sx^2+sy^2));
A(3,6) = -Cda * Cw * sin(rho) * squareroot + Cda * (Cw*cos(rho) - sx) * (Cw*sx*sin(rho) - Cw*sy*cos(rho)) / squareroot;
A(4,3) = sin(phi) * (-2 * Cdh * sx) - Cda * (sx-Cw*cos(rho))*(sy-Cw*sin(rho)) / squareroot;
A(4,4) = sin(phi) * (-2 * Cdh * sy) - Cda * squareroot - Cda * (sy-Cw*sin(rho))^2 / squareroot;
A(4,5) = cos(phi) * (tanh(u_t) - Cdh*(sx^2+sy^2));
A(4,6) = Cda * Cw * cos(rho) * squareroot + Cda * (Cw*sin(rho) - sy) * (Cw*sx*sin(rho) - Cw*sy*cos(rho)) / squareroot;

% order of process noise is [vd, vr, vrho, vb]
L = zeros(7,4);
L(3,1) = -cos(phi) * Cdh * (sx^2 + sy^2);
L(4,1) = -sin(phi) * Cdh * (sx^2 + sy^2);
L(5,2) = Cr * u_r;
L(6,3) = 1;
L(7,4) = 1;

% solve ODE
Q_d = estConst.DragNoise;
Q_r = estConst.RudderNoise;
Q_rho = estConst.WindAngleNoise;
Q_b = estConst.GyroDriftNoise;
Q_c = diag([Q_d, Q_r, Q_rho, Q_b]);

P = reshape(P, [7,7]);
dPdt = A * P + P * A' + L * Q_c * L';
dPdt = dPdt(:);
end