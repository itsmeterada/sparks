#version 450

// Rainforest - Ported from Shadertoy (single-pass, no temporal reprojection)
// https://www.shadertoy.com/view/4ttSWf
// Original Author: Inigo Quilez - 2016
// License: Educational use only (see original for full terms)

layout(location = 0) in vec2 vUV;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PushConstants {
    vec2 iResolution;
    float iTime;
    int preRotate;
    vec4 iMouse;
    int mode;
    int iFrame;
};

layout(set = 0, binding = 0) uniform sampler2D iPrevFrame;

#define LOWQUALITY
#define ZERO (min(iFrame,0))

//==========================================================================================
// general utilities
//==========================================================================================

float sdEllipsoidY( in vec3 p, in vec2 r )
{
    float k0 = length(p/r.xyx);
    float k1 = length(p/(r.xyx*r.xyx));
    return k0*(k0-1.0)/k1;
}

vec2 smoothstepd( float a, float b, float x)
{
    if( x<a ) return vec2( 0.0, 0.0 );
    if( x>b ) return vec2( 1.0, 0.0 );
    float ir = 1.0/(b-a);
    x = (x-a)*ir;
    return vec2( x*x*(3.0-2.0*x), 6.0*x*(1.0-x)*ir );
}

mat3 setCamera( in vec3 ro, in vec3 ta, float cr )
{
    vec3 cw = normalize(ta-ro);
    vec3 cp = vec3(sin(cr), cos(cr),0.0);
    vec3 cu = normalize( cross(cw,cp) );
    vec3 cv = normalize( cross(cu,cw) );
    return mat3( cu, cv, cw );
}

//==========================================================================================
// hashes
//==========================================================================================

float hash1( vec2 p )
{
    p  = 50.0*fract( p*0.3183099 );
    return fract( p.x*p.y*(p.x+p.y) );
}

float hash1( float n )
{
    return fract( n*17.0*fract( n*0.3183099 ) );
}

vec2 hash2( vec2 p )
{
    const vec2 k = vec2( 0.3183099, 0.3678794 );
    float n = 111.0*p.x + 113.0*p.y;
    return fract(n*fract(k*n));
}

//==========================================================================================
// noises
//==========================================================================================

vec4 noised( in vec3 x )
{
    vec3 p = floor(x);
    vec3 w = fract(x);
    vec3 u = w*w*w*(w*(w*6.0-15.0)+10.0);
    vec3 du = 30.0*w*w*(w*(w-2.0)+1.0);

    float n = p.x + 317.0*p.y + 157.0*p.z;

    float a = hash1(n+0.0);
    float b = hash1(n+1.0);
    float c = hash1(n+317.0);
    float d = hash1(n+318.0);
    float e = hash1(n+157.0);
    float f = hash1(n+158.0);
    float g = hash1(n+474.0);
    float h = hash1(n+475.0);

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return vec4( -1.0+2.0*(k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z),
                      2.0* du * vec3( k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                                      k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                                      k3 + k6*u.x + k5*u.y + k7*u.x*u.y ) );
}

float noise( in vec3 x )
{
    vec3 p = floor(x);
    vec3 w = fract(x);
    vec3 u = w*w*w*(w*(w*6.0-15.0)+10.0);

    float n = p.x + 317.0*p.y + 157.0*p.z;

    float a = hash1(n+0.0);
    float b = hash1(n+1.0);
    float c = hash1(n+317.0);
    float d = hash1(n+318.0);
    float e = hash1(n+157.0);
    float f = hash1(n+158.0);
    float g = hash1(n+474.0);
    float h = hash1(n+475.0);

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return -1.0+2.0*(k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z);
}

vec3 noised( in vec2 x )
{
    vec2 p = floor(x);
    vec2 w = fract(x);
    vec2 u = w*w*w*(w*(w*6.0-15.0)+10.0);
    vec2 du = 30.0*w*w*(w*(w-2.0)+1.0);

    float a = hash1(p+vec2(0,0));
    float b = hash1(p+vec2(1,0));
    float c = hash1(p+vec2(0,1));
    float d = hash1(p+vec2(1,1));

    float k0 = a;
    float k1 = b - a;
    float k2 = c - a;
    float k4 = a - b - c + d;

    return vec3( -1.0+2.0*(k0 + k1*u.x + k2*u.y + k4*u.x*u.y),
                 2.0* du * vec2( k1 + k4*u.y, k2 + k4*u.x ) );
}

float noise( in vec2 x )
{
    vec2 p = floor(x);
    vec2 w = fract(x);
    vec2 u = w*w*w*(w*(w*6.0-15.0)+10.0);

    float a = hash1(p+vec2(0,0));
    float b = hash1(p+vec2(1,0));
    float c = hash1(p+vec2(0,1));
    float d = hash1(p+vec2(1,1));

    return -1.0+2.0*(a + (b-a)*u.x + (c-a)*u.y + (a - b - c + d)*u.x*u.y);
}

//==========================================================================================
// fbm constructions
//==========================================================================================

const mat3 m3  = mat3( 0.00,  0.80,  0.60,
                      -0.80,  0.36, -0.48,
                      -0.60, -0.48,  0.64 );
const mat3 m3i = mat3( 0.00, -0.80, -0.60,
                       0.80,  0.36, -0.48,
                       0.60, -0.48,  0.64 );
const mat2 m2 = mat2(  0.80,  0.60,
                      -0.60,  0.80 );
const mat2 m2i = mat2( 0.80, -0.60,
                       0.60,  0.80 );

float fbm_4( in vec2 x )
{
    float f = 1.9, s = 0.55, a = 0.0, b = 0.5;
    for( int i=ZERO; i<4; i++ ) { float n = noise(x); a += b*n; b *= s; x = f*m2*x; }
    return a;
}

float fbm_4( in vec3 x )
{
    float f = 2.0, s = 0.5, a = 0.0, b = 0.5;
    for( int i=ZERO; i<4; i++ ) { float n = noise(x); a += b*n; b *= s; x = f*m3*x; }
    return a;
}

vec4 fbmd_7( in vec3 x )
{
    float f = 1.92, s = 0.5, a = 0.0, b = 0.5;
    vec3 d = vec3(0.0);
    mat3 m = mat3(1.0,0.0,0.0, 0.0,1.0,0.0, 0.0,0.0,1.0);
    for( int i=ZERO; i<7; i++ ) { vec4 n = noised(x); a += b*n.x; d += b*m*n.yzw; b *= s; x = f*m3*x; m = f*m3i*m; }
    return vec4( a, d );
}

vec4 fbmd_8( in vec3 x )
{
    float f = 2.0, s = 0.65, a = 0.0, b = 0.5;
    vec3 d = vec3(0.0);
    mat3 m = mat3(1.0,0.0,0.0, 0.0,1.0,0.0, 0.0,0.0,1.0);
    for( int i=ZERO; i<8; i++ ) { vec4 n = noised(x); a += b*n.x; if(i<4) d += b*m*n.yzw; b *= s; x = f*m3*x; m = f*m3i*m; }
    return vec4( a, d );
}

float fbm_9( in vec2 x )
{
    float f = 1.9, s = 0.55, a = 0.0, b = 0.5;
    for( int i=ZERO; i<9; i++ ) { float n = noise(x); a += b*n; b *= s; x = f*m2*x; }
    return a;
}

vec3 fbmd_9( in vec2 x )
{
    float f = 1.9, s = 0.55, a = 0.0, b = 0.5;
    vec2 d = vec2(0.0);
    mat2 m = mat2(1.0,0.0,0.0,1.0);
    for( int i=ZERO; i<9; i++ ) { vec3 n = noised(x); a += b*n.x; d += b*m*n.yz; b *= s; x = f*m2*x; m = f*m2i*m; }
    return vec3( a, d );
}

//==========================================================================================
// specifics to the actual painting
//==========================================================================================

const vec3  kSunDir = vec3(-0.624695,0.468521,-0.624695);
const float kMaxTreeHeight = 4.8;
const float kMaxHeight = 840.0;

vec3 fog( in vec3 col, float t )
{
    vec3 ext = exp2(-t*0.00025*vec3(1,1.5,4));
    return col*ext + (1.0-ext)*vec3(0.55,0.55,0.58);
}

//------------------------------------------------------------------------------------------
// clouds
//------------------------------------------------------------------------------------------

vec4 cloudsFbm( in vec3 pos )
{
    return fbmd_8(pos*0.0015+vec3(2.0,1.1,1.0)+0.07*vec3(iTime,0.5*iTime,-0.15*iTime));
}

float cloudsShadowFlat( in vec3 ro, in vec3 rd )
{
    float t = (900.0-ro.y)/rd.y;
    if( t<0.0 ) return 1.0;
    vec3 pos = ro + rd*t;
    return cloudsFbm(pos).x;
}

// forward declaration
float terrainShadow( in vec3 ro, in vec3 rd, in float mint );

vec4 renderClouds( in vec3 ro, in vec3 rd, float tmin, float tmax, inout float resT )
{
    vec4 sum = vec4(0.0);

    float tl = ( 600.0-ro.y)/rd.y;
    float th = (1200.0-ro.y)/rd.y;
    if( tl>0.0 ) tmin = max( tmin, tl ); else return sum;
    if( th>0.0 ) tmax = min( tmax, th );

    float t = tmin;
    float lastT = -1.0;
    float thickness = 0.0;
    for(int i=ZERO; i<128; i++)
    {
        vec3  pos = ro + t*rd;
        float d = abs(pos.y-900.0)-40.0;
        vec3 gra = vec3(0.0,sign(pos.y-900.0),0.0);
        vec4 n = cloudsFbm(pos);
        d += 400.0*n.x * (0.7+0.3*gra.y);

        float dt = max(0.2,0.011*t);

        if( d<0.0 )
        {
            float nnd = -d;
            float den = min(-d/100.0,0.25);

            if( den>0.001 )
            {
                float kk;
                // shadow sample
                vec3 spos = pos+kSunDir*70.0;
                float sd = abs(spos.y-900.0)-40.0;
                vec4 sn = cloudsFbm(spos);
                sd += 400.0*sn.x * (0.7+0.3*sign(spos.y-900.0));
                kk = -sd;

                float sha = 1.0-smoothstep(-200.0,200.0,kk); sha *= 1.5;

                vec3 nor = normalize(gra);
                float dif = clamp( 0.4+0.6*dot(nor,kSunDir), 0.0, 1.0 )*sha;
                float fre = clamp( 1.0+dot(nor,rd), 0.0, 1.0 )*sha;
                float occ = 0.2+0.7*max(1.0-kk/200.0,0.0) + 0.1*(1.0-den);

                vec3 lin  = vec3(0.0);
                lin += vec3(0.70,0.80,1.00)*1.0*(0.5+0.5*nor.y)*occ;
                lin += vec3(0.10,0.40,0.20)*1.0*(0.5-0.5*nor.y)*occ;
                lin += vec3(1.00,0.95,0.85)*3.0*dif*occ + 0.1;

                vec3 col = vec3(0.8,0.8,0.8)*0.45;
                col *= lin;
                col = fog( col, t );

                float alp = clamp(den*0.5*0.125*dt,0.0,1.0);
                col.rgb *= alp;
                sum = sum + vec4(col,alp)*(1.0-sum.a);
                thickness += dt*den;
                if( lastT<0.0 ) lastT = t;
            }
        }
        else
        {
            dt = abs(d)+0.2;
        }
        t += dt;
        if( sum.a>0.995 || t>tmax ) break;
    }

    if( lastT>0.0 ) resT = min(resT,lastT);
    sum.xyz += max(0.0,1.0-0.0125*thickness)*vec3(1.00,0.60,0.40)*0.3*pow(clamp(dot(kSunDir,rd),0.0,1.0),32.0);

    return clamp( sum, 0.0, 1.0 );
}

//------------------------------------------------------------------------------------------
// terrain
//------------------------------------------------------------------------------------------

vec2 terrainMap( in vec2 p )
{
    float e = fbm_9( p/2000.0 + vec2(1.0,-2.0) );
    float a = 1.0-smoothstep( 0.12, 0.13, abs(e+0.12) );
    e = 600.0*e + 600.0;
    e += 90.0*smoothstep( 552.0, 594.0, e );
    return vec2(e,a);
}

vec4 terrainMapD( in vec2 p )
{
    vec3 e = fbmd_9( p/2000.0 + vec2(1.0,-2.0) );
    e.x  = 600.0*e.x + 600.0;
    e.yz = 600.0*e.yz;
    vec2 c = smoothstepd( 550.0, 600.0, e.x );
    e.x  = e.x  + 90.0*c.x;
    e.yz = e.yz + 90.0*c.y*e.yz;
    e.yz /= 2000.0;
    return vec4( e.x, normalize( vec3(-e.y,1.0,-e.z) ) );
}

vec3 terrainNormal( in vec2 pos )
{
    return terrainMapD(pos).yzw;
}

float terrainShadow( in vec3 ro, in vec3 rd, in float mint )
{
    float res = 1.0;
    float t = mint;
    for( int i=ZERO; i<32; i++ )
    {
        vec3  pos = ro + t*rd;
        vec2  env = terrainMap( pos.xz );
        float hei = pos.y - env.x;
        res = min( res, 32.0*hei/t );
        if( res<0.0001 || pos.y>kMaxHeight ) break;
        t += clamp( hei, 2.0+t*0.1, 100.0 );
    }
    return clamp( res, 0.0, 1.0 );
}

vec2 raymarchTerrain( in vec3 ro, in vec3 rd, float tmin, float tmax )
{
    float tp = (kMaxHeight+kMaxTreeHeight-ro.y)/rd.y;
    if( tp>0.0 ) tmax = min( tmax, tp );

    float dis, th;
    float t2 = -1.0;
    float t = tmin;
    float ot = t;
    float odis = 0.0;
    float odis2 = 0.0;
    for( int i=ZERO; i<400; i++ )
    {
        th = 0.001*t;
        vec3  pos = ro + t*rd;
        vec2  env = terrainMap( pos.xz );
        float hei = env.x;

        float dis2 = pos.y - (hei+kMaxTreeHeight*1.1);
        if( dis2<th )
        {
            if( t2<0.0 )
            {
                t2 = ot + (th-odis2)*(t-ot)/(dis2-odis2);
            }
        }
        odis2 = dis2;

        dis = pos.y - hei;
        if( dis<th ) break;

        ot = t;
        odis = dis;
        t += dis*0.8*(1.0-0.75*env.y);
        if( t>tmax ) break;
    }

    if( t>tmax ) t = -1.0;
    else t = ot + (th-odis)*(t-ot)/(dis-odis);

    return vec2(t,t2);
}

//------------------------------------------------------------------------------------------
// trees
//------------------------------------------------------------------------------------------

float treesMap( in vec3 p, in float rt, out float oHei, out float oMat, out float oDis )
{
    oHei = 1.0;
    oDis = 0.0;
    oMat = 0.0;

    float base = terrainMap(p.xz).x;

    float bb = fbm_4(p.xz*0.075);

    float d = 20.0;
    vec2 n = floor( p.xz/2.0 );
    vec2 f = fract( p.xz/2.0 );
    for( int j=0; j<=1; j++ )
    for( int i=0; i<=1; i++ )
    {
        vec2  g = vec2( float(i), float(j) ) - step(f,vec2(0.5));
        vec2  o = hash2( n + g );
        vec2  v = hash2( n + g + vec2(13.1,71.7) );
        vec2  r = g - f + o;

        float height = kMaxTreeHeight * (0.4+0.8*v.x);
        float width = 0.5 + 0.2*v.x + 0.3*v.y;

        if( bb<0.0 ) width *= 0.5; else height *= 0.7;

        vec3  q = vec3(r.x,p.y-base-height*0.5,r.y);

        float k = sdEllipsoidY( q, vec2(width,0.5*height) );

        if( k<d )
        {
            d = k;
            oMat = 0.5*hash1(n+g+111.0);
            if( bb>0.0 ) oMat += 0.5;
            oHei = (p.y - base)/height;
            oHei *= 0.5 + 0.5*length(q) / width;
        }
    }

    if( rt<1200.0 )
    {
        p.y -= 600.0;
        float s = fbm_4( p*3.0 );
        s = s*s;
        float att = 1.0-smoothstep(100.0,1200.0,rt);
        d += 4.0*s*att;
        oDis = s*att;
    }

    return d;
}

float treesShadow( in vec3 ro, in vec3 rd )
{
    float res = 1.0;
    float t = 0.02;
    for( int i=ZERO; i<64; i++ )
    {
        float kk1, kk2, kk3;
        vec3 pos = ro + rd*t;
        float h = treesMap( pos, t, kk1, kk2, kk3 );
        res = min( res, 32.0*h/t );
        t += h;
        if( res<0.001 || t>50.0 || pos.y>kMaxHeight+kMaxTreeHeight ) break;
    }
    return clamp( res, 0.0, 1.0 );
}

vec3 treesNormal( in vec3 pos, in float t )
{
    float kk1, kk2, kk3;
    vec3 n = vec3(0.0);
    for( int i=ZERO; i<4; i++ )
    {
        vec3 e = 0.5773*(2.0*vec3((((i+3)>>1)&1),((i>>1)&1),(i&1))-1.0);
        n += e*treesMap(pos+0.005*e, t, kk1, kk2, kk3);
    }
    return normalize(n);
}

//------------------------------------------------------------------------------------------
// sky
//------------------------------------------------------------------------------------------

vec3 renderSky( in vec3 ro, in vec3 rd )
{
    vec3 col = vec3(0.42,0.62,1.1) - rd.y*0.4;

    float t = (2500.0-ro.y)/rd.y;
    if( t>0.0 )
    {
        vec2 uv = (ro+t*rd).xz;
        float cl = fbm_9( uv*0.00104 );
        float dl = smoothstep(-0.2,0.6,cl);
        col = mix( col, vec3(1.0), 0.12*dl );
    }

    float sun = clamp( dot(kSunDir,rd), 0.0, 1.0 );
    col += 0.2*vec3(1.0,0.6,0.3)*pow( sun, 32.0 );

    return col;
}

//==========================================================================================
// main
//==========================================================================================

void main()
{
    vec2 fragCoord = vec2(vUV.x, 1.0 - vUV.y) * iResolution;

    // per-frame jitter for temporal accumulation (only when mode==1)
    vec2 o = (mode == 1) ? hash2( vec2(float(iFrame), 1.0) ) - 0.5 : vec2(0.0);
    vec2 p = (2.0*(fragCoord+o)-iResolution.xy)/ iResolution.y;

    // camera
    float time = iTime;
    vec3 ro = vec3(0.0, 401.5, 6.0);
    vec3 ta = vec3(0.0, 403.5, -90.0 + ro.z );

    ro.x -= 80.0*sin(0.01*time);
    ta.x -= 86.0*sin(0.01*time);

    mat3 ca = setCamera( ro, ta, 0.0 );
    vec3 rd = ca * normalize( vec3(p,1.5));

    float resT = 2000.0;

    // sky
    vec3 col = renderSky( ro, rd );

    // raycast terrain and tree envelope
    const float tmax = 2000.0;
    int obj = 0;
    vec2 tt = raymarchTerrain( ro, rd, 15.0, tmax );
    if( tt.x>0.0 )
    {
        resT = tt.x;
        obj = 1;
    }

    // raycast trees
    float hei, mid, displa;
    if( tt.y>0.0 )
    {
        float tf = tt.y;
        float tfMax = (tt.x>0.0)?tt.x:tmax;
        for(int i=ZERO; i<64; i++)
        {
            vec3  pos = ro + tf*rd;
            float dis = treesMap( pos, tf, hei, mid, displa);
            if( dis<(0.000125*tf) ) break;
            tf += dis;
            if( tf>tfMax ) break;
        }
        if( tf<tfMax )
        {
            resT = tf;
            obj = 2;
        }
    }

    // shade
    if( obj>0 )
    {
        vec3 pos  = ro + resT*rd;
        vec3 epos = pos + vec3(0.0,4.8,0.0);

        float sha1  = terrainShadow( pos+vec3(0,0.02,0), kSunDir, 0.02 );
        sha1 *= smoothstep(-0.325,-0.075,cloudsShadowFlat(epos, kSunDir));

        vec3 tnor = terrainNormal( pos.xz );
        vec3 nor;

        vec3 speC = vec3(1.0);
        // terrain
        if( obj==1 )
        {
            nor = normalize( tnor + 0.8*(1.0-abs(tnor.y))*0.8*fbmd_7( (pos-vec3(0,600,0))*0.15*vec3(1.0,0.2,1.0) ).yzw );

            col = vec3(0.18,0.12,0.10)*.85;
            col = 1.0*mix( col, vec3(0.1,0.1,0.0)*0.2, smoothstep(0.7,0.9,nor.y) );

            float dif = clamp( dot( nor, kSunDir), 0.0, 1.0 );
            dif *= sha1;

            float bac = clamp( dot(normalize(vec3(-kSunDir.x,0.0,-kSunDir.z)),nor), 0.0, 1.0 );
            float foc = clamp( (pos.y/2.0-180.0)/130.0, 0.0,1.0);
            float dom = clamp( 0.5 + 0.5*nor.y, 0.0, 1.0 );
            vec3  lin  = 1.0*0.2*mix(0.1*vec3(0.1,0.2,0.1),vec3(0.7,0.9,1.5)*3.0,dom)*foc;
                  lin += 1.0*8.5*vec3(1.0,0.9,0.8)*dif;
                  lin += 1.0*0.27*vec3(1.1,1.0,0.9)*bac*foc;
            speC = vec3(4.0)*dif*smoothstep(20.0,0.0,abs(pos.y/2.0-310.0)-20.0);

            col *= lin;
        }
        // trees
        else
        {
            vec3 gnor = treesNormal( pos, resT );
            nor = normalize( gnor + 2.0*tnor );

            vec3  ref = reflect(rd,nor);
            float occ = clamp(hei,0.0,1.0) * pow(1.0-2.0*displa,3.0);
            float dif = clamp( 0.1 + 0.9*dot( nor, kSunDir), 0.0, 1.0 );
            dif *= sha1;
            if( dif>0.0001 )
            {
                float a = clamp( 0.5+0.5*dot(tnor,kSunDir), 0.0, 1.0);
                a = a*a;
                a *= occ;
                a *= 0.6;
                a *= smoothstep(60.0,200.0,resT);
                float sha2 = treesShadow( pos+kSunDir*0.1, kSunDir );
                dif *= a+(1.0-a)*sha2;
            }
            float dom = clamp( 0.5 + 0.5*nor.y, 0.0, 1.0 );
            float bac = clamp( 0.5+0.5*dot(normalize(vec3(-kSunDir.x,0.0,-kSunDir.z)),nor), 0.0, 1.0 );
            float fre = clamp(1.0+dot(nor,rd),0.0,1.0);

            vec3 lin  = 12.0*vec3(1.2,1.0,0.7)*dif*occ*(2.5-1.5*smoothstep(0.0,120.0,resT));
                 lin += 0.55*mix(0.1*vec3(0.1,0.2,0.0),vec3(0.6,1.0,1.0),dom*occ);
                 lin += 0.07*vec3(1.0,1.0,0.9)*bac*occ;
                 lin += 1.10*vec3(0.9,1.0,0.8)*pow(fre,5.0)*occ*(1.0-smoothstep(100.0,200.0,resT));
            speC = dif*vec3(1.0,1.1,1.5)*1.2;

            float brownAreas = fbm_4( pos.zx*0.015 );
            col = vec3(0.2,0.2,0.05);
            col = mix( col, vec3(0.32,0.2,0.05), smoothstep(0.2,0.9,fract(2.0*mid)) );
            col *= (mid<0.5)?0.65+0.35*smoothstep(300.0,600.0,resT)*smoothstep(700.0,500.0,pos.y):1.0;
            col = mix( col, vec3(0.25,0.16,0.01)*0.825, 0.7*smoothstep(0.1,0.3,brownAreas)*smoothstep(0.5,0.8,tnor.y) );
            col *= 1.0-0.5*smoothstep(400.0,700.0,pos.y);
            col *= lin;
        }

        // specular
        vec3  ref = reflect(rd,nor);
        float fre = clamp(1.0+dot(nor,rd),0.0,1.0);
        float spe = 3.0*pow( clamp(dot(ref,kSunDir),0.0, 1.0), 9.0 )*(0.05+0.95*pow(fre,5.0));
        col += spe*speC;

        col = fog(col,resT);
    }

    // clouds
    {
        vec4 res = renderClouds( ro, rd, 0.0, resT, resT );
        col = col*(1.0-res.w) + res.xyz;
    }

    // sun glare
    float sun = clamp( dot(kSunDir,rd), 0.0, 1.0 );
    col += 0.25*vec3(0.8,0.4,0.2)*pow( sun, 4.0 );

    // gamma
    col = pow( clamp(col*1.1-0.02,0.0,1.0), vec3(0.4545) );
    // contrast
    col = col*col*(3.0-2.0*col);
    // color grade
    col = pow( col, vec3(1.0,0.92,1.0) );
    col *= vec3(1.02,0.99,0.9);
    col.z = col.z+0.1;

    // temporal accumulation: blend with previous frame (mode==1 to enable)
    if( mode == 1 )
    {
        vec2 uv = vec2(vUV.x, vUV.y); // sample history in swapchain UV space (no Y flip)
        vec3 ocol = textureLod( iPrevFrame, uv, 0.0 ).xyz;
        if( iFrame == 0 ) ocol = col;
        col = mix( ocol, col, 0.1 );
    }

    // vignette
    vec2 q = fragCoord/iResolution.xy;
    col *= 0.5 + 0.5*pow( 16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y), 0.05 );

    outColor = vec4( col, 1.0 );
}
