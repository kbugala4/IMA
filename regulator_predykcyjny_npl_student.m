clear all;
%najprzydaniejsza funkcja: help
%przydatne funkcje: kron, eye, size, length, cell2mat, str2double, interp1, drawnow


%% TODO - Zadeklarować nastawy regulatora NPL, horyzonty predykcji i
%sterowania, parametry psi oraz lambda (pamiętajmy, że są to macierze)
%; ograniczenia na sterowanie i przyrosty sterowań. 
du1 = 10;
du2 = -10;
N=15; Nu=3;



%% TODO - Zadeklarować parametry filtru rozszerzonego Kalmana, wyznaczyć
% macierze kowariancji - P, Q oraz R
%     Parametry filtru Kalmana:
    nu=2; nx=3; ny=3;
    P_est = 1*eye(nx);
    Q_est = 1*eye(nx);
    R_est = 10*eye(nx);
    

%% TODO - zadeklarować parametry robota, okres próbkowania 
global L; global R; global Tp;
L=0.287; R=0.033;
Tp=1/30;
t=[]; x=[];
x0=[0 0 0];

tmin_odcinek = 0;
tmax_odcinek = Tp;

%% TODO -zadeklarować trajektorię zadaną robota. Umożliwic wybór pomiędzy
% dwiema trajektoriami. Odpowiednio przygotować trajektorię drugą 
% (zastosować interpolację).
[yzad_1, yzad_2, yzad_3]=y_zadane();
figure;
plot(yzad_1, yzad_2);
title("Prosta trajektoria zadana")
xlabel("x")
ylabel("y")


if_hard_traj = 0;

if if_hard_traj == 1
    [yhard_1, yhard_2, yhard_3]=hard_traj();
    yzad_1=yhard_1;
    yzad_2=yhard_2;
    yzad_3=yhard_3;
end

kmin = 2;
kmax = 286;

% inicjalizacja błędu średniokwadratowego
msq = 0;
msq_e = 0;

% pozycja w chwili
distance = zeros(1, kmax);

% Inicjacja macierzy
xk= zeros(3,kmax+N);
uk=zeros(2,kmax+Nu-1);
u_vals = zeros(2, 286);
yk=zeros(3,kmax+N);
tk=(0:kmax-1)*Tp;

% Linearyzacja za pomocą mierzonego stanu
xk_lin = zeros(3,kmax+N);

% Linearyzacja za pomocą estymowanego stanu
xk_lin_est = zeros(3,kmax+N);

% Stan estymowany
xk_est = zeros(3,kmax+N);

% Dykretyzacja modelu ciągłego
xk_disc = zeros(3,kmax+N);

yk_szum=zeros(3,kmax+N);
zk=zeros(3,kmax+N);

% trajektoria swobodna
stan = 0; % stan==1 => stan mierzony, stan==0 => stan estymowany

%%
for k = kmin:kmax
    %% Symulacja obiektu
    u1_aktualne = uk(1,k-1);
    u2_aktualne = uk(2,k-1);
    u_vals(1, k) = u1_aktualne;
    u_vals(2, k) = u2_aktualne;

    [t_odcinek,x_odcinek] = ode23(@(t,x) model_niel_ciagly(t,x, u1_aktualne, u2_aktualne),[tmin_odcinek tmax_odcinek],x0);
    t=[t; t_odcinek(1:end)]; x=[x; x_odcinek(1:end,:)];
    x0 = x(end,:);
    tmin_odcinek = tmin_odcinek + Tp;
    tmax_odcinek = tmax_odcinek + Tp;

    xk(1,k)=x_odcinek(end,1);
    xk(2,k)=x_odcinek(end,2);
    xk(3,k)=x_odcinek(end,3);
    yk(:,k)=xk(:,k);

    [A,B,C] = mod_lin(xk(:,k),u1_aktualne, u2_aktualne);

    xk_disc(:,k) =  modx_niel_dysk(xk(:,k-1),u1_aktualne, u2_aktualne);

   %% TODO - zaimplementować rozszerzony  filtr kalmana    
    xk_est(:, k)=xk_disc(:,k);
    P_est=A*P_est*A'+Q_est;

    zk(:,k) = rand(1,3)*0.01;
    yk_szum(:,k) =yk(:,k) + zk(:,k);

    yk_est(:,k) = yk_szum(:,k) - (C*xk_est(:,k));
    S = C*P_est*C'+R_est;
    K=P_est*C'/S;
    xk_est(:,k) = xk_est(:,k)+K*yk_est(:,k);



   %% TODO - zlinearyzować model dyskretny z wykorzystaniem stanu mierzonego
    xk_lin(:,k) = A*xk_disc(:,k-1)+B*(uk(:,k-1));
 
   %% TODO - zlinearyzować model dyskretny z wykorzystaniem stanu estymnowanego
    xk_lin_est(:,k) = A*xk_est(:,k-1)+B*(uk(:,k-1));

   %% TODO - wyznaczyć macierze P oraz Cf
    P_est=(eye(3,3)-K*C)*P_est;
    Cf=kron(eye(N,N),C);

   %% TODO - wyznaczyć zakłócenie v(k) dla stanu mierzonego
   if stan == 1
       xmod = modx_niel_dysk(xk(:,k-1),u1_aktualne, u2_aktualne);
       vk = xk(:,k) - xmod; 
   end
   
   %% TODO - wyznaczyć zakłócenie v(k) dla stanu estomowanego
   if stan == 0
        xmod = modx_niel_dysk(xk_est(:,k-1),u1_aktualne, u2_aktualne);
        vk = xk_est(:,k) - xmod;
   end

   %% TODO - wyznaczyć d(k) na podstawie nieliniowego modelu dyskretnego
   ymod = xmod + vk;
   dk = yk(:,k) - ymod;

   %% TODO - wyznaczyć trajektorię swobodną x0 na podsatawie nieliniowego 
   % modelu dyskretnego -- stan mierzony
    if stan == 0
        x0_traj(:, 1) = modx_niel_dysk(xk(:,k),u1_aktualne, u2_aktualne)+vk;
        for p=2:N
            x0_traj(:,p) = modx_niel_dysk(x0_traj(:, p-1),u1_aktualne, u2_aktualne) + vk;
        end
    end  
 
   %% TODO - wyznaczyć trajektorię swobodną x0 na podstawie nieliniowego 
   % modelu dyskretnego -- stan estymowany
    if stan == 1
        x0_traj(:, 1) = modx_niel_dysk(xk_est(:,k),u1_aktualne, u2_aktualne)+vk;
        for p=2:N
            x0_traj(:,p) = modx_niel_dysk(x0_traj(:,p-1), u1_aktualne, u2_aktualne) + vk;
        end
    end


   %% TODO - wyznaczyć trajektorię swobodną y0 
   y0_traj=zeros(N*ny,1);
   for col   = 1:N
       for row = 1:ny
        y0_traj((col-1)*3 + row) = x0_traj(row,col);
       end
   end


   %% TODO - wyznaczyć wartości zadane na horyzoncie N 
   yzad=[];
   for i=1:N
       if k+i>length(yzad_1)
        yzad = [yzad, yzad_1(end), yzad_2(end), yzad_3(end)];
       else
        yzad=[yzad,yzad_1(k+i),yzad_2(k+i),yzad_3(k+i)];
       end
   end
   
    %% TODO - prawo sterowania
   M=zeros(nx*N,nu*Nu);
   for row=1:N
       for col=1:Nu
            sum_A = zeros(nx,nx);
            if row>=col
                sum_A = eye(nx,nx);
                if row>col
                    for iter=1:row-col
                        sum_A = sum_A + A^iter;
                    end
                end
            end
            M(row*nx-2:row*nx,col*nu-1:col*nu)=sum_A*B;
       end
   end
    psi=zeros(1,3);
    psi(1) = 100;
    psi(2) = 100;
    psi(3) = 1;

    PsiP = kron(eye(N,N),diag([psi]));

    lambda=zeros(1,2);
    lambda(1)=1.2;
    lambda(2)=1;

    LambdaP = kron(eye(Nu,Nu),diag([lambda]));
    K=inv(M' * Cf' * PsiP * Cf * M + LambdaP)* M' * Cf' * PsiP;
    K12=K(1:nu,:);
    
   %% TODO - narzucić ograniczenia na przyrosty sterowania i 
   % wartości sterowania   
    duk=K*(yzad'-y0_traj);
    if duk(1)<-10
        duk(1)=-10;
    end
    if duk(2)>10
        duk(2)=10;
    end
    uk(:,k)=uk(:,k-1)+duk(1:2);
end

%% wykresy y na yzad 
if stan == 1
    figure;
    plot(yk(1,1:kmax));
    hold on
    plot(yzad_1(1:kmax));
    hold off
    title("Wykres położenia robota wględem osi x, na tle wartości zadanej położenia dla stanu mierzonego")
    legend("poł. x", "poł. zadane x")
    xlabel("k")
    ylabel("y")
    
    figure;
    plot(yk(2,1:kmax));
    hold on
    plot(yzad_2(1:kmax));
    hold off
    title("Wykres położenia robota wględem osi y, na tle wartości zadanej położenia dla stanu mierzonego ")
    legend("poł. y", "poł. zadane y")
    xlabel("k")
    ylabel("y")
    
    figure;
    plot(yk(3,1:kmax));
    hold on
    plot(yzad_3(1:kmax));
    hold off
    title("Wykres położenia kątowego względem położenia zadanego dla stanu mierzonego")
    legend("poł. kątowe", "poł. kątowe")
    xlabel("k")
    ylabel("y")
else
    figure;
    plot(yk_est(1,1:kmax));
    hold on
    plot(yzad_1(1:kmax));
    hold off
    title("Wykres położenia robota wględem osi x, na tle wartości zadanej położenia dla stanu mierzonego")
    legend("poł. x", "poł. zadane x")
    xlabel("k")
    ylabel("y")
    
    figure;
    plot(yk_est(2,1:kmax));
    hold on
    plot(yzad_2(1:kmax));
    hold off
    title("Wykres położenia robota wględem osi y, na tle wartości zadanej położenia dla stanu mierzonego ")
    legend("poł. y", "poł. zadane y")
    xlabel("k")
    ylabel("y")
    
    figure;
    plot(yk_est(3,1:kmax));
    hold on
    plot(yzad_3(1:kmax));
    hold off
    title("Wykres położenia kątowego względem położenia zadanego dla stanu mierzonego")
    legend("poł. kątowe", "poł. kątowe")
    xlabel("k")
    ylabel("y")
end



%% TODO wyznaczyc błąd średniokwadratowy
for i=1:kmax
    if stan == 1
        distance(i)=(yzad_1(i)-yk(1, i))^2+(yzad_2(i)-yk(2, i))^2;
    else
        distance(i)=(yzad_1(i)-yk_est(1, i))^2+(yzad_2(i)-yk_est(2, i))^2;
    end
end

if stan == 1
    msq = (sum(distance))/kmax;
else
    msq_e = (sum(distance))/kmax;
end


%% TODO -- wykresy

% wykres 1 - u(t)
tiledlayout(1,2)
nexttile
plot(uk(1, :));
title('Sterowanie prędkością koła 1')
legend('sterowanie koła 1')
ylabel("u")
xlabel("k")

nexttile
plot(uk(2, :))
title('Sterowanie prędkością koła 2')
legend('sterowanie koła 2')
ylabel("u")
xlabel("k")

figure;
plot(uk(1, :))
hold on;
plot(uk(2, :))
hold off;
title('Sterowanie prędkością kół')
legend('sterowanie koła 1','sterowanie koła 2')
ylabel("u")
xlabel("k")

% wykres 2 - y(t)

tiledlayout(1,3)
nexttile
plot(yk(1, 1:k));
title('Pozycja X')
legend('pozycja X')
ylabel("y")
xlabel("k")

nexttile
plot(yk(2, 1:k))
title('Pozycja Y')
legend('pozycja Y')
ylabel("y")
xlabel("k")

nexttile
plot(yk(3, 1:k))
title('Pozycja kątowa')
legend('pozycja kątowa')
ylabel("y")
xlabel("k")



% Wykres 4 - estymowana trajektoria
figure
plot(yk_est(1,:), yk_est(2,:));
title('estymowana trajektoria robota'); xlabel('x_est'); ylabel('y_est');


% wykres 5 - rzeczywista i estymowana trajektoria
figure
plot(yk(1,:), yk(2,:));
hold on;
plot(yk_est(1,:), yk_est(2,:));
hold off;
legend("trajektoria rzeczywista", "trajektoria estymowana")
title('rzeczywista i estymowana trajektoria robota'); xlabel('x'); ylabel('y');


%% Funkcje - dobrze jest długie, bądź też często powtarzające się
% fragmenty kodu zawrzeć w funkcjach

% model nieliniowy ciągły
function dxdt = model_niel_ciagly(t,x,u1_aktualne, u2_aktualne)
global R; global L;
dxdt(1,1) = 0.5*R*(u1_aktualne+u2_aktualne)*cos(x(3));
dxdt(2,1) = 0.5*R*(u1_aktualne+u2_aktualne)*sin(x(3));
dxdt(3,1) = (u2_aktualne-u1_aktualne)*R/L;
end

%model nieliniowy dyskretny x(k)
function modx_niel_dysk = modx_niel_dysk(x, u1_aktualne, u2_aktualne)
    global R; global L; global Tp;
    modx_niel_dysk(1,1) = x(1) + (0.5*R*(u1_aktualne+u2_aktualne)*cos(x(3)))*Tp;
    modx_niel_dysk(2,1) = x(2) + (0.5*R*(u1_aktualne+u2_aktualne)*sin(x(3)))*Tp;
    modx_niel_dysk(3,1) = x(3) + ((u2_aktualne-u1_aktualne)*R/L)*Tp;
end

%model nieliniowy dyskretny y(k)
function mody_niel_dysk = mody_niel_dysk(x, u1_aktualne, u2_aktualne)
    mody_niel_dysk = x;
end

%linearyzacja modelu dyskretnego, wyznaczenie macierzy A B C
function [A,B,C] = mod_lin(x, u1_aktualne, u2_aktualne)
    global R;global L;global Tp;
    A=zeros(3,3);
    B=zeros(3,2);
    C=eye(3,3); 
    
    A(1,1) = 1;
    A(1,3) = (-0.5*R*Tp)*(u1_aktualne+u2_aktualne)*sin(x(3));
    A(2,2) = 1;
    A(2,3) = (0.5*R*Tp)*(u1_aktualne+u2_aktualne)*cos(x(3));
    A(3,3) = 1;

    B(1,1) = 0.5*R*Tp*cos(x(3));
    B(1,2) = 0.5*R*Tp*cos(x(3));
    B(2,1) =  0.5*R*Tp*sin(x(3));
    B(2,2) =  0.5*R*Tp*sin(x(3));
    B(3,1) = -(R/L)*Tp;
    B(3,2) = (R/L)*Tp;
end

%wyznaczenie trajektorii zadanej yzad
function [y1zad, y2zad, y3zad]=y_zadane()
y1zad = [-1.4999997928738598, -1.4679014037236815, -1.442962438508312, -1.4180036368668656, -1.3930463611043482, -1.368078404189328, -1.3431104472743076, -1.3181363868435714, -1.2931638522917641, -1.2681897918610279, -1.2432157314302916, -1.2182401451206264, -1.1932660846898901, -1.1683057571695148, -1.1433408520123525, -1.1183667915816162, -1.093389679393022, -1.0684064636887118, -1.0434217221054727, -1.0184339287643756, -0.9934430836654204, -0.9684522385664653, -0.9434598675885812, -0.9184659707317682, -0.8934705479960261, -0.868475125260284, -0.843478176645613, -0.8184812280309419, -0.7934842794162709, -0.7684873308015998, -0.7434888563079998, -0.7184903818143997, -0.6934919073207997, -0.6684934328271996, -0.6434949583335996, -0.6184964838399996, -0.5934964834674705, -0.5684980089738705, -0.5434995344802704, -0.5184995341077414, -0.4934995337352124, -0.46850105924161234, -0.4435010588690833, -0.4185010584965543, -0.39350258400295424, -0.3685025836304252, -0.3435025832578962, -0.31850258288536715, -0.2935041083917671, -0.2685041080192381, -0.24350410764670904, -0.21850410727418001, -0.19350410690165099, -0.16850410652912196, -0.1435056320355219, -0.11850563166299288, -0.09350563129046385, -0.06850563091793482, -0.04350563054540579, -0.01850715605180575, 0.0064913184417942915, 0.031489792935394334, 0.05648674155006539, 0.08148063840687847, 0.10647300938476256, 0.13146385448371767, 0.15644859606695682, 0.18115562768512028, 0.20576347717289956, 0.2293489877782573, 0.2531053968236616, 0.2779039811775643, 0.3024736836921189, 0.32642082760364666, 0.3500688992450929, 0.3737062897340362, 0.3967897861717571, 0.4193621131682672, 0.44145989181786227, 0.46304650102624656, 0.4863207323300909, 0.5092714773009899, 0.5320269097689785, 0.5543673031682825, 0.576300286893547, 0.5978212833079848, 0.6189470770798149, 0.6399385935058941, 0.6604494580693423, 0.6808855545652701, 0.7010515704907672, 0.7209917563347741, 0.7408602258691186, 0.7605928921787832, 0.7804506805606248, 0.8000795871031183, 0.8196230444255885, 0.8391863381741356, 0.8586092510612158, 0.8779924910961423, 0.8974123522253645, 0.9167803334710012, 0.9362947990938206, 0.9558031612009241, 0.9753618773126842, 0.9949007569983674, 1.0144304814104768, 1.0340395515268934, 1.0535845347282926, 1.0731203626561179, 1.0927141739832447, 1.1122606830635728, 1.1318514426328417, 1.1514284692917496, 1.1709795560088647, 1.1904772369634653, 1.2100191684070065, 1.2291338537504313, 1.248485050327849, 1.2680330852871062, 1.2869707686747685, 1.3063830004093457, 1.3252840627027123, 1.3448992363348449, 1.3649599666142418, 1.3837465879879343, 1.4038057923884022, 1.4245501164279855, 1.4442110664279877, 1.4652056346119249, 1.485722602691089, 1.5071978227376572, 1.5281389851590799, 1.5503817223069287, 1.5735750820275367, 1.596246591154431, 1.6194246920857491, 1.6430468237854026, 1.667042795822658, 1.691313426067131, 1.715834300455958, 1.7405520132266243, 1.7645983392685363, 1.788675182889028, 1.812948864891359, 1.8373751347865888, 1.8619280526329245, 1.8865969372778633, 1.9113329605956775, 1.9361178120392193, 1.9609545433663467, 1.9858462063349176, 2.0107668610031393, 2.0357271885235146, 2.060699723075322, 2.085690568174277, 2.110687516788948, 2.135687517161477, 2.160685991655077, 2.1856753108751032, 2.2106585265794134, 2.2356280093733627, 2.260589862772667, 2.2855562938087584, 2.310505940176631, 2.3354174395712786, 2.3602923178716306, 2.385113790409468, 2.4098345549379925, 2.434186056765702, 2.4582995214804892, 2.48248317662601, 2.5063250348914377, 2.529736595298891, 2.5527544789426653, 2.575351220002039, 2.5975359737505865, 2.6192919555200884, 2.6406359499787637, 2.661732752050943, 2.6831545663349967, 2.7046740368705056, 2.725621302807644, 2.745913966684247, 2.765489467464226, 2.7839205590474645, 2.800906643284952, 2.816452297813475, 2.830827603203465, 2.842923245473548, 2.854420743203468, 2.8662752966027707, 2.876890836311736, 2.887724576707546, 2.898599515834439, 2.9096804486167454, 2.920697294484034, 2.929060636893814, 2.937040983692418, 2.9450381151592406, 2.953106962935726, 2.960209929350162, 2.9658343190824095, 2.9710146780463216, 2.976379668360641, 2.9811541435294426, 2.98475979543864, 2.987852752027697, 2.990996062621411, 2.9937853693036, 2.9958819269520287, 2.9976046442628554, 2.9992663264165227, 3.0007662654037173, 3.002029693156919, 3.0031618953222274, 3.0042696834246723, 3.005259978849585, 3.0060335994665817, 3.0066729427378274, 3.0072619320044165, 3.0077364803513316, 3.008027923226768, 3.0081271053571523, 3.008027923226768, 3.0077547908984794, 3.007335174193008, 3.0067889095364304, 3.006135833354824, 3.005395782074265, 3.0046007991522625, 3.0037463069520296, 3.002830779594637, 3.0018511653222273, 3.000804412376942, 2.999704253669142, 2.9985705256249044, 2.9974017023653, 2.996199309769258, 2.9949618219578493, 2.993689238931074, 2.9923922418414346, 2.9910830377203634, 2.9897570489310734, 2.9884096978367776, 2.987036406800689, 2.9856325981860206, 2.9841936943559855, 2.9827151176737967, 2.9811999198973123, 2.979646575147603, 2.978077971608604, 2.976529204495682, 2.9749926444141916, 2.9734576102116304, 2.971911894856566, 2.97033871368078, 2.9687365408053434, 2.967113005624901, 2.9654543752290916, 2.9637469167075547, 2.962033354670302, 2.9603701466377057, 2.95875118909405, 2.9571627491289743, 2.9555941455899752, 2.95403469732455, 2.952485930211628, 2.9509615771615696, 2.949457060537588, 2.9479708544607544, 2.9466204516086005, 2.945602690362966, 2.9449511400602884, 2.9446886888845025, 2.9449160448449216, 2.9457766405608705, 2.9474459521091827, 2.950166594239567, 2.954159819396727, 2.9596773976039454, 2.9669405813059253, 2.9762484427727482, 2.988121306719199, 3.0000002741813656, 3.0];
y2zad = [0.6000002384185787, 0.5879229066956437, 0.5896502016432574, 0.5910967348679375, 0.5925570010029784, 0.593811273482606, 0.5950853823883104, 0.5962358951007669, 0.5974138736339452, 0.598523187615319, 0.5996645450542015, 0.6007738590355753, 0.6019182682323159, 0.6033342838784161, 0.6046480656362743, 0.6057848454383699, 0.6068468571729451, 0.6077730656828404, 0.6086428166723632, 0.6094103337736438, 0.6101320745070549, 0.6107729436572296, 0.6113802434709665, 0.611921930490757, 0.6124346258108968, 0.61289696712638, 0.6133364202579283, 0.613733148779465, 0.6141100408749249, 0.6144533636339471, 0.6147814276036794, 0.6150789739948319, 0.6153643133545526, 0.6156252386514094, 0.6158770086746923, 0.6161074163929694, 0.6163286688376726, 0.6165331366141569, 0.6167299749959962, 0.6169130804674747, 0.6170900824232373, 0.6172548773475679, 0.6174166205140406, 0.6175875189540871, 0.6177477362416308, 0.6178896429820266, 0.6180193426909906, 0.6181337836106646, 0.6182329657410488, 0.6182970526560663, 0.6183535101764388, 0.618445062912178, 0.6185091498271955, 0.618326044355717, 0.6181917670099661, 0.6182253363464039, 0.6182833197457054, 0.6182955267771373, 0.6183718207235867, 0.6186388495361594, 0.6189440253219569, 0.6192369940763225, 0.6196291449610722, 0.6201570990705019, 0.6207796576735287, 0.6214815619808629, 0.6223574164861017, 0.626176691445357, 0.6305849556712015, 0.6388735300134609, 0.6466600901880835, 0.6498339183603772, 0.654446650362706, 0.6616259107235916, 0.6697359572311594, 0.677878047196236, 0.6874788774174245, 0.6982256427142826, 0.7099154011892548, 0.7225267905373354, 0.7316515465326798, 0.7415667078132397, 0.75191827046749, 0.7631395841112631, 0.7751390960088198, 0.7878588227608585, 0.8012270480577168, 0.8148058446467754, 0.8290972266956711, 0.8434984720274539, 0.8582750835757675, 0.8733553450309497, 0.8885286851008001, 0.903879027126413, 0.9190661001066243, 0.9345491935990591, 0.950137572737594, 0.9657045895711232, 0.9814440307236278, 0.9972323000018601, 1.0129763187911518, 1.028784424495461, 1.0444109506072206, 1.0600451061136251, 1.0756151747050122, 1.091211183238192, 1.1068193988028039, 1.1223269063581025, 1.1379152854966375, 1.1535143457876753, 1.1690416897690508, 1.1846270171497277, 1.2001574128889612, 1.2157061191753424, 1.2312868689192324, 1.246933231457069, 1.2625261882323908, 1.2786394697224974, 1.2944674118528834, 1.3100527392335604, 1.3263735402580092, 1.3421267143208748, 1.3584887140764064, 1.37398859223706, 1.3889071105257695, 1.405401861748123, 1.4203234317946904, 1.434274542842422, 1.449716437603774, 1.4632891306771167, 1.4775744092102965, 1.4903750075455715, 1.5040285722021505, 1.515440620712047, 1.5247744221206627, 1.5353075643674625, 1.544677986870374, 1.5528643273243912, 1.5598757410030881, 1.5658709193150795, 1.5707461024931941, 1.5744921352638581, 1.5813295987446505, 1.5880587248214848, 1.5940416961020443, 1.5993654876852812, 1.6040774018179942, 1.6081362397691006, 1.6117571504675876, 1.6150255831334785, 1.617875924972827, 1.6201998385816747, 1.6221926364629322, 1.6236040744722455, 1.624766794216134, 1.6254320774291724, 1.6258913669867976, 1.6259081516550165, 1.62572199442568, 1.6249819431451211, 1.6240679416666577, 1.6228396091288229, 1.6214541110613023, 1.6201510104559471, 1.6185610446119423, 1.6164721163581586, 1.6139696749146193, 1.610991159245236, 1.6072664887795778, 1.6016039520741057, 1.5950060515851643, 1.5886690763930797, 1.581146493273172, 1.5723787929472106, 1.5626253748331234, 1.551927437661993, 1.5404024741113513, 1.5280871052754943, 1.515069832132303, 1.5016558304675751, 1.4887682570333478, 1.4760454785234511, 1.4623964915036591, 1.447795356032179, 1.4322466497457977, 1.4153551700019076, 1.3970125793965504, 1.3774340268587135, 1.3569796198156379, 1.335100041852888, 1.3129015551939798, 1.290890751643337, 1.2682573894896674, 1.24572626122424, 1.2232149693848893, 1.2008059114337808, 1.1783632841462346, 1.1548037134826696, 1.1311129172312118, 1.1074251727376119, 1.0837633681858048, 1.0597933360903422, 1.0354342048679879, 1.0109774173941783, 0.9865603027725225, 0.9620195919576187, 0.9372805168819465, 0.9124727772544698, 0.8876711411427092, 0.8628283062998658, 0.8379152810262891, 0.8129747899319906, 0.7880312470798341, 0.7630754971962457, 0.7381075402812254, 0.7131334798504891, 0.6881578935408239, 0.6631777295943717, 0.6381899362532746, 0.6131975652753905, 0.5882051942975064, 0.5632097715617643, 0.5382112970681643, 0.5132112966956353, 0.4882112963231062, 0.4632128218295062, 0.4382158732148351, 0.41322197635802205, 0.38823113125906694, 0.3632418120390408, 0.3382540186979437, 0.31326927711470454, 0.28828606141039437, 0.2633043715850132, 0.23832725939641897, 0.21335167308675373, 0.1883760867770885, 0.16340355222528125, 0.13843254355240298, 0.1134630607584537, 0.08849662972236239, 0.06353019868627108, 0.03856376765017977, 0.01359886249301745, -0.011364516785215883, -0.03632637018452023, -0.06128669770489559, -0.08624549934634196, -0.11120277510885934, -0.13615547323458976, -0.16110817136032018, -0.18605934360712162, -0.21101051585392305, -0.23596321397965347, -0.2609159121053839, -0.2858686102311143, -0.31081825659898676, -0.3357679029668592, -0.3607144975768737, -0.38565956630795917, -0.4106015832811867, -0.4355420743754852, -0.4604871431065707, -0.48543373771658516, -0.5103833840844576, -0.535334556331259, -0.5602857285780605, -0.5852384267037909, -0.6101911248295213, -0.6351468747131097, -0.6601026245966981, -0.6850660038749314, -0.7100446419424546, -0.7350370129203387, -0.7600354874139388, -0.7850339619075388, -0.810018703490778, -0.8349637722218635, -0.8598142364593517, -0.8844938022567934, -0.9088773475420115, -0.9327985515117465, -0.9560010665059284, -0.9780027147829973, -0.9999997854232792, -1.0];
y3zad = [-0.3598746467427098, -0.1795074106141673, 0.0635210452414569, 0.0581680365512319, 0.05431859175602125, 0.05058932296423632, 0.04851064311366909, 0.046585889130945725, 0.0457627909276729, 0.04502972214120022, 0.04502834841646676, 0.04508932114136444, 0.05123091560114153, 0.054623318624393444, 0.049031801192517335, 0.043990419100099674, 0.03977499207345758, 0.03592675845855297, 0.03275164318201656, 0.029789072655157404, 0.027255429992840415, 0.024966572997738395, 0.02298200262670118, 0.021089025271101774, 0.019501831069060824, 0.018036684985348165, 0.016724115123502564, 0.015473066111836853, 0.014405058966583383, 0.013428156674031426, 0.012512317753269234, 0.011657898260509085, 0.010925525099580837, 0.010254172719737909, 0.009643844336995278, 0.009033233095042385, 0.008514458383107083, 0.008026440583545838, 0.007598962590724077, 0.007202023913967231, 0.0068360396346456445, 0.006530868174228915, 0.006652733882021937, 0.0066224197426678275, 0.0060425913309755065, 0.005432075476731756, 0.004882773695447827, 0.004272565328153957, 0.0032654689070046113, 0.0024108840008875572, 0.002960196431594858, 0.003112782915026643, -0.0023803665979056, -0.006347764710442288, -0.002014218901463809, 0.0018310526411410377, 0.001403807671599254, 0.0017700176827812849, 0.006866556711594105, 0.011444290678856401, 0.01196305009821376, 0.013702789478745711, 0.018403391820155768, 0.023012512447492327, 0.026491953766606874, 0.031560108550906636, 0.09420537293544758, 0.16531425195678034, 0.2576026610773864, 0.3273385981105061, 0.22201052376737476, 0.15643521957563655, 0.23842633754390294, 0.31082392644418694, 0.3310536888808263, 0.36294094584203557, 0.41925027542993387, 0.46546320751910764, 0.5076588513337575, 0.4511901796633094, 0.39071993599795235, 0.41736288591321696, 0.44620132750308017, 0.48304502290790813, 0.5172077946854051, 0.548993590288186, 0.5691774738047372, 0.5913633805529722, 0.611213491164558, 0.623119564985277, 0.6399366054965638, 0.6498548993982455, 0.6566669170275701, 0.6570148719613037, 0.6603847142266542, 0.6705800984108946, 0.6727106042879364, 0.6765758637646485, 0.682281026583881, 0.6823905713802939, 0.682890915243485, 0.6798740150446926, 0.6754034210369305, 0.6739688336145029, 0.6729917840331735, 0.6739497880658677, 0.6716906890749383, 0.6711902269820301, 0.673535124376584, 0.6719718563816964, 0.6716239206476449, 0.6717096808049223, 0.6707565387861251, 0.6720386196511552, 0.6745550641902812, 0.6748600936740152, 0.6869384820470881, 0.6929916315730702, 0.6793307113885263, 0.692198048271715, 0.6965163265156247, 0.6976184233000688, 0.6911268995955242, 0.6540859539582277, 0.6799831393534855, 0.6800498417187152, 0.6158101492195709, 0.628915284852175, 0.6198410806685584, 0.5910585752074546, 0.5728676443706412, 0.5576480717334842, 0.5259121160339221, 0.42832396228393876, 0.4087640381022431, 0.40955768152216127, 0.3588957211835067, 0.30894002536105236, 0.2632214633401111, 0.2192119346429541, 0.17333361587746013, 0.21372029740755918, 0.27478256164723047, 0.2570969040607125, 0.22813023460943008, 0.20210008365557447, 0.17633759711142533, 0.15421088450685416, 0.13823273932447416, 0.12268940196199613, 0.10367724346303718, 0.08644355737127944, 0.06814150777512268, 0.051506780794718106, 0.036570543675582774, 0.02249315331916972, 0.00952177778370209, -0.003387541593934974, -0.01852657358809151, -0.03308715718647525, -0.04286098752536533, -0.05230076151418231, -0.053797250835281606, -0.057893842021818014, -0.07364932995519856, -0.09196128982647728, -0.10984498865626968, -0.13448575415776126, -0.1890101126204911, -0.24777693539930548, -0.2616777066538604, -0.2809539188862109, -0.33198383300909773, -0.3795654196538136, -0.42148163695404306, -0.4606446150248084, -0.4971104881327395, -0.5313743314319501, -0.5570012421573514, -0.5539763237395282, -0.5377711514779756, -0.5557164159618853, -0.6006004689167268, -0.6474818190737096, -0.7065462263722279, -0.7828064884950958, -0.8617460507705992, -0.9289560721815449, -1.0119896850577672, -1.0793416973464756, -1.084831604458891, -1.1044999705410476, -1.127417595479788, -1.1216839665058493, -1.1161702700253027, -1.1130173552099352, -1.172073709131506, -1.2377827484069828, -1.2455426358227446, -1.24368016794846, -1.262434166430344, -1.31329545344607, -1.3529715000226605, -1.358287677978638, -1.3665773856814558, -1.4023556123738434, -1.436413579128394, -1.4457448454558453, -1.4518582866225236, -1.4729133758452972, -1.4943357366837295, -1.5030547929795337, -1.507520870190645, -1.5155009583166805, -1.5228648420542894, -1.5259813855509734, -1.5288221553409302, -1.535510035744454, -1.5425333615860315, -1.5462271218622656, -1.5495235899457018, -1.5554758310279397, -1.5629837473234922, -1.5707963267948966, -1.5782427054736738, -1.5846516891634856, -1.5901150878526777, -1.5947858625963447, -1.598662718553084, -1.6015014172292246, -1.6037919808978256, -1.6062046138862822, -1.6087076083693652, -1.611334870321766, -1.613748785146107, -1.6154879558099298, -1.6168625708604256, -1.6182386269141746, -1.6196132661844915, -1.6210198997145284, -1.6222116743209058, -1.622943116251002, -1.6235237431711091, -1.624288842145871, -1.6252368105131858, -1.6263676238255085, -1.6276812443034399, -1.6291776197064183, -1.630708031902215, -1.6322062033097418, -1.6332741477668271, -1.6331846784112871, -1.6325431424964016, -1.6322671236199184, -1.6324498818076012, -1.6332151367908538, -1.6343458907353332, -1.6353548061785081, -1.6364875221837067, -1.63816836197299, -1.6392706731111721, -1.6383835560877753, -1.6364875221837067, -1.6349893524269463, -1.6339784852492367, -1.6333978846310626, -1.6330000285833202, -1.6322975836037188, -1.6314105003724166, -1.630645280268876, -1.627559370605395, -1.618179105490669, -1.6041895091296194, -1.5890776670194116, -1.571498273819935, -1.5490334232379432, -1.5201703479757145, -1.4828640748701096, -1.4360660608062268, -1.379322747020901, -1.3121374410266702, -1.2326525314148635, -1.1326180419969163, -1.0757946400118483, -1.0756574577776012, 0.0];
y1zad=y1zad-y1zad(1);
y2zad=y2zad-y2zad(1);
y3zad=y3zad-y3zad(1);
end

function [yhard_1, yhard_2, yhard_3]=hard_traj()
    traj = [[0.0, 0.0, 0],
    [1.4730020591525754, 0.0, 0.0],
    [1.5222047988305931, 0.34347347496292124,1.4285138243982216],
    [1.7042799239390183, 0.6810996302421143, 1.0762204679460083],
    [0.5818680945688905, 1.0275670158354115, 2.84219064322596],
    [0.7365056769967078, 1.3257989123769383, 1.0924470103664876],
    [1.7131457173841742, 1.754845129500227, 0.41392734072255266],
    [0.3171500325533403, 1.8475212055670576, 3.0753028453438724],
    [0.6158217951049396, 2.2100885443724376, 0.8817291437001219],
    [1.4279733153511263, 2.7902370709291935, 0.6202823407614878],
    [1.3267012850015751, 3.1335423737457515, 1.8576515462547434],
    [-0.019499561034802326, 2.895362710518681, -2.9664775835341888],
    [0.2027824149650952, 3.3318333468011114, 1.099759202993532],
    [0.13360039789141975, 3.6432415486944993, 1.7894046647703694],
    [-0.8173259940151567, 3.335243176838586, -2.828362352276737],
    [0.2749577981388338, 4.549468319410257, 0.8382173515010083],
    [0.23336044650066512, 4.982947446042545, 1.6664649878740063],
    [-0.20615456694940715, 5.046025529618686, 2.9990485364686874],
    [-0.7845918741778575, 4.894830461311038, -2.885927354177291],
    [-0.5605750551093678, 5.724797933258136, 1.3071680435582547],
    [-1.4443403837245299, 5.031670136583825, -2.47650501598296],
    [-1.723704310045556, 5.141018278715469, 2.7685061489053133],
    [-1.823927965951969, 5.606190333030981, 1.78300736550122],
    [-1.785330572088784, 6.528171132024477, 1.5289572022291653],
    [-2.5271579629554513, 5.501733169517296, -2.1966085235294663],
    [-2.7855720343628247, 5.669980612603367, 2.564460729343636],
    [-3.005398422794059, 6.0782001623621555, 2.0647678172704786],
    [-3.3808833920485917, 5.724009867867732, -2.3853699787979687],
    [-3.636444427847847, 6.203055207003518, 2.060867716395617],
    [-3.9794369953573048, 5.267301279939902, -1.9221307074458285],
    [-4.251840327513052, 5.4858805124997465, 2.465383758717595],
    [-4.535292015877113, 5.533807214252677, 2.974094423358792],
    [-4.981330046638902, 6.514225073552475, 1.997756444793164],
    [-5.308074824753766, 6.396203551624831, -2.7949716152552604],
    [-5.363791358606724, 5.3746696464315455, -1.6252843695751509],
    [-5.803617324849837, 5.76229377447102, 2.419198589482772],
    [-5.872230668490588, 5.1345521492336115, -1.6796660336574738],
    [-6.347021180730608, 5.453996967004747, 2.5493475545045787],
    [-6.154816809042005, 4.51973119141821, -1.367899455128385],
    [-7.197877824204763, 5.6134844057875135, 2.332475679274327],
    [-6.876074907993874, 4.631193258499389, -1.2542106301843632],
    [-7.715363946556151, 5.163147708776804, 2.5766791619220886],
    [-7.2589469555664605, 4.214936276834764, -1.1221836485261896],
    [-8.378826363951699, 4.84335964452809, 2.6302272412114127],
    [-8.28736459869609, 4.317542325471592, -1.3985773152694216],
    [-8.246594421784586, 3.8865969240152674, -1.476470711841804],
    [-7.8297929219533025, 3.26756893857059, -0.9782043963907524],
    [-8.665805039584166, 3.4015639407550102, 2.982665581969019],
    [-8.354549669464735, 2.91147044568917, -1.0049714102805711],
    [-9.686026822994233, 3.10520090872126, 2.997106167623474],
    [-8.997964846599224, 2.5064384733541316, -0.7161139578481581],
    [-8.701902106004933, 2.108306867253461, -0.9313842813704314],
    [-8.372330483644223, 1.7519195675898316, -0.8244705174588035],
    [-8.890722678399479, 1.5410027230651475, -2.7551802250895574],
    [-8.78656074674664, 1.2365960572899914, -1.2411048417274788],
    [-9.88845562621513, 0.9364870519613769, -2.8756850880279416],
    [-8.625916028648806, 0.6665483306240388, -0.21063477095761096],
    [-8.620037422663184, 0.38395611249616735, -1.549996892638956],
    [-8.994868293326597, 0.022832152529269734, -2.3748170001349287],
    [-8.422056684419104, -0.14680498483822435, -0.28791931432229595],
    [-8.826532579752286, -0.57045877498996, -2.3330405471446887],
    [-8.859098243503233, -0.9147047398739353, -1.665115622551366],
    [-8.333769504634141, -1.0177940598918283, -0.19377539056700407],
    [-7.876319437148462, -1.0975221401499762, -0.17255478867214832],
    [-7.485943901620422, -1.166769205041422, -0.17555960166543474],
    [-8.069888802149956, -1.8940296442307383, -2.247326048016737],
    [-7.731101348664755, -2.0085328591946054, -0.32592626198098523],
    [-7.640465234870278, -2.3214104964682702, -1.2888290345453068],
    [-7.100575118817362, -2.188960035652562, 0.240577197351343],
    [-6.873691970782341, -2.3388115266970106, -0.5837063964785206],
    [-6.959844162606886, -2.9042698954725203, -1.7219917334189678],
    [-6.793799688191775, -3.1960206033001293, -1.0533836772087775],
    [-6.095054369547637, -2.584812088435935, 0.7186730229987527],
    [-6.085559025820613, -3.1422219148914867, -1.5537632122470844],
    [-5.894444052129897, -3.4201954609619363, -0.9684890454786704],
    [-5.474386296104706, -3.0998666805085553, 0.6515055246691674],
    [-5.218433125760335, -3.1721354405255036, -0.27518790872071264],
    [-4.94624610096523, -3.1681309496982792, 0.014711215357501677],
    [-4.820594015261521, -4.114632086039164, -1.438813767296474],
    [-4.432590955306307, -3.286498543460168, 1.132642476148582],
    [-4.17474938017026, -3.568412668523696, -0.8299676015529416],
    [-3.854048831225861, -4.579915259226652, -1.263768367776534],
    [-3.6087794004286082, -3.599409236755472, 1.325680476135787],
    [-3.1780374915941856, -4.47146463274685, -1.1120095044852216],
    [-3.0956375772799882, -3.301647018560534, 1.5004742180106923],
    [-2.41833200887809, -4.645571663529858, -1.1039730969500519],
    [-2.539190593011296, -3.250591360808514, 1.657218725156907],
    [-2.102874703471354, -3.559436239560299, -0.6159729932410217],
    [-2.1571645564269617, -2.78007579577826, 1.6403434732142175],
    [-1.498889265987632, -3.3849713552224965, -0.7431647710272719],
    [-1.399484615781235, -2.9739938680708873, 1.3334804371368214],
    [-0.5862370361595826, -3.548955228391834, -0.6154046820156166],
    [-0.9867250828682934, -2.553669862660406, 1.9533571712070237],
    [-0.9173153700874526, -2.2122645629514603, 1.3702240442593707],
    [0.06504422723035219, -2.7208090139980157, -0.47768857973394935],
    [0.28915616557759716, -2.4618964818102422, 0.8573211577651498],
    [-0.31245797684591237, -1.6268929960226957, 2.1951439687841923],
    [-0.0977313145168246, -1.427373257559188, 0.7487047887841177],
    [0.09239982051626772, -1.2037937582767362, 0.8660723489521254],
    [-0.3536597466108464, -0.6855287133239575, 2.281457219746539],
    [1.2242293826658042, -1.0126709234421747, -0.20443266185115058],
    [0.16954918573640043, -0.3223824735274704, 2.56206031702847],
    [0.0, 0.0, 2.0549686325218066]]
    yhard_1 = traj(:, 1)';
    yhard_2 = traj(:, 2)';
    yhard_3 = traj(:, 3)';

    data = readtable('ima_difficult_trajectory.txt', 'Whitespace', '[],');
    assignin('base', 'data', data);

    yhard_process_1=zeros(1, length(yhard_1)*5);
    yhard_process_2=zeros(1, length(yhard_1)*5);
    yhard_process_3=zeros(1, length(yhard_1)*5);

    % plot hard trajectory
    int_coef = 3;
    for i=1:(length(yhard_1)-1)
        first_1=yhard_1(i);
        sec_1=yhard_1(i+1);
        first_2=yhard_2(i);
        sec_2=yhard_2(i+1);
        first_3=yhard_3(i);
        sec_3=yhard_3(i+1);

        points_1=linspace(first_1, sec_1, int_coef);
        points_2=linspace(first_2, sec_2, int_coef);
        points_3=linspace(first_3, sec_3, int_coef);

        f_idx = (i-1)*int_coef+1;
        s_idx = (i)*int_coef+1;
        it=1;
        for idx=(f_idx:s_idx-1)
            yhard_process_1(idx)=points_1(it);        
            yhard_process_2(idx)=points_2(it);
            yhard_process_3(idx)=points_3(it);
            it = it+1;
        end
    end
    assignin('base', 'yhard_process_1', yhard_process_1);
%     figure;
    yhard_1 = yhard_process_1;
    yhard_2 = yhard_process_2;
    yhard_3 = yhard_process_3;
%     figure;
%     plot(yhard_process_1, yhard_process_2);
%     hold on;
%     plot(yhard_1, yhard_2);

end

