precision mediump float;

const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float EPSILON = 0.0001;
const int MAX_ITERS = 8;
const float HALF_PI =  1.5707964;

const float FREQ_MUL = 2.0;
const float BASE_SIZE = 1.3;

const float distance = 15.0;
const float noise = 0.2;
const float displ = 2.0;
const float light = 0.7;
const float ncolor = 0.05;
const float round = 0.6;
const float size = 1.0;
const vec2 dimensions = vec2(1000.0, 1000.0);

uniform float time;
uniform vec4 freq_1;
uniform vec4 freq_2;

varying vec3 vposition;
varying vec3 vcolor;

int id = 0;

float sphere(vec3 p, float s) {
    return length(p) - s;
}

float box(vec3 p, vec3 b) {
  vec3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float disp(vec3 p, float amt) {
    return sin(amt*p.x)*sin(amt*p.y)*sin(amt*p.z);
}

mat3 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    );
}


float onion(float sdf, float thickness) {
    return abs(sdf)-thickness;
}

float octa(vec3 p, in float s) {
    p = abs(p);
    return (p.x+p.y+p.z-s)*0.57735027;
}


vec3 rep(in vec3 p, in vec3 c) {
    vec3 q = mod(p,c)-0.5*c;
    return q;
}



float smmin( float d1, float d2) {
    float k = 0.5;
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float scene(vec3 p) {
	vec3 q = p;//rep(p, vec3(16.0, 8.0, 8.0));
    //vec3 rp = rotateY(time + sin(time)) * q;

    float o_plane = p.y + 1.6;

    vec3 displacement = q + disp(q, displ * abs(cos(time / 8.0)));

    float sphere_0 = octa(
        vec3(-7.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_1.x * FREQ_MUL
    );
    float sphere_1 = octa(
        vec3(-5.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_1.y * FREQ_MUL
    );
    float sphere_2 = octa(
        vec3(-3.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_1.z * FREQ_MUL
    );
    float sphere_3 = octa(
        vec3(-1.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_1.a * FREQ_MUL
    );
    float sphere_4 = octa(
        vec3(1.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_2.x * FREQ_MUL
    );
    float sphere_5 = octa(
        vec3(3.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_2.y * FREQ_MUL
    );
    float sphere_6 = octa(
        vec3(5.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_2.z * FREQ_MUL
    );
    float sphere_7 = octa(
        vec3(7.0, 0.0, 0.0) + displacement,
        BASE_SIZE + freq_2.a * FREQ_MUL
    );

    float o_sphere_total =
        smmin(sphere_0, smmin(sphere_1, smmin(sphere_2, smmin(sphere_3,
        smmin(sphere_4, smmin(sphere_5, smmin(sphere_6, sphere_7))))))
    );

    float o_onion = onion(onion(onion(o_sphere_total, 0.4), 0.2), 0.05);

    float o_box_sub = box(p + vec3(0.0, abs(sin(time / 2.0)) * 10.0, 0.0), vec3(10.0));

    return smmin(o_plane, max(o_onion, o_box_sub));
}

float shortest_dist(vec3 eye, vec3 dir, float start, float end) {
    float depth = start;
    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        float dist = scene(eye + depth * dir);
        if (dist < EPSILON || depth >=  end) break;
        depth += dist / (1.0 + displ);
    }
    return depth;
}

vec3 estimate_normal(vec3 p) {
    vec2 e = vec2(1.0,-1.0)*0.5773*0.0005;
    return normalize( e.xyy * scene(p + e.xyy) +
                      e.yyx * scene(p + e.yyx) +
                      e.yxy * scene(p + e.yxy) +
                      e.xxx * scene(p + e.xxx) );
}

vec3 phong_contrib(vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye,
                          vec3 light_pos, vec3 light_intensity) {
    vec3 N = estimate_normal(p);
    vec3 L = normalize(light_pos - p);
    vec3 V = normalize(eye - p);
    vec3 R = normalize(reflect(-L, N));

    float dotLN = dot(L, N);
    float dotRV = dot(R, V);

    if (dotLN < 0.0) {
        return vec3(0.0, 0.0, 0.0);
    }

    if (dotRV < 0.0) {
        return light_intensity * (k_d * dotLN);
    }
    return light_intensity * (k_d * dotLN + k_s * pow(dotRV, alpha));
}


float softshadow(vec3 eye, vec3 dir, float mint, float tmax ) {
    float res = 1.0;
    float t = mint;
    for(int i = 0; i < 16; i++) {
        float h = scene(eye + dir * t);
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.02, 0.10);
        if(h < 0.001 || t > tmax) break;
    }
    return clamp(res, 0.0, 1.0);
}


float calc_AO(vec3 pos, vec3 nor) {
    float occ = 0.0;
    float sca = 1.0;
    for(int i=0; i<5; i++) {
        float hr = 0.01 + 0.12*float(i)/4.0;
        vec3 aopos =  nor * hr + pos;
        float dd = scene(aopos);
        occ += -(dd-hr)*sca;
        sca *= 0.95;
    }
    return clamp( 1.0 - 3.0*occ, 0.0, 1.0 );
}

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec3 lighting(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye) {
    const vec3 ambient_light = vec3(0.6);
    vec3 color = ambient_light * k_a;
    vec3 normal = estimate_normal(p);

    float occ = calc_AO(p, normal);

    vec3 light_pos = vec3(4.0 * sin(time),
                          5.0,
                          4.0 * cos(time));
    vec3 light_intensity = vec3(light);


	color = mix(color, normal, ncolor);
	if(id == 1) {
		color = mix(color, vec3(1.0), 0.9);
	} else {
		color = mix(color, vec3(1.0), 0.6);
	}

    color += phong_contrib(k_d, k_s, alpha, p, eye,
                                  light_pos,
                                  light_intensity);
    color = mix(
        color,
        color * occ * softshadow(p, normalize(light_pos), 0.02, 5.0),
        light// + tan(time / 7.2) * 4.0
    );

    color = mix(color, vec3(rand(vposition.xy * time)), noise);

    return color;
}


vec4 render(vec3 cam_pos, vec3 v_dir) {
    float dist = shortest_dist(cam_pos, v_dir, MIN_DIST, MAX_DIST);

    if (dist > MAX_DIST - EPSILON) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }

    vec3 p = cam_pos + dist * v_dir;
    vec3 color = lighting(vec3(0.2), vec3(0.2), vec3(1.0), 20.0, p, cam_pos);
    return vec4(color, 1.0);
}

mat4 view_matrix(vec3 eye, vec3 center, vec3 up) {
    vec3 f = normalize(center - eye);
    vec3 s = normalize(cross(f, up));
    vec3 u = cross(s, f);
    return mat4(
        vec4(s, 0.0),
        vec4(u, 0.0),
        vec4(-f, 0.0),
        vec4(0.0, 0.0, 0.0, 1)
    );
}

vec3 ray_dir(float fieldOfView, vec2 size, vec2 fragCoord) {
    vec2 xy = fragCoord - size / 2.0;
    float z = size.y / tan(radians(fieldOfView) / 2.0);
    return normalize(vec3(xy, -z));
}

void main() {
    vec3 dir = ray_dir(45.0, dimensions, vposition.xy * dimensions + (dimensions / 2.0));

    vec3 input_cam_pos = vec3(0.63, 0.7, 1.8);
    vec3 cam_pos = vec3(
        (cos(input_cam_pos.x) * cos(input_cam_pos.y)) + cos(time / 8.5),
        input_cam_pos.y - 0.25 + (sin(time / 3.5) * 0.25),
        (sin(input_cam_pos.x) * cos(input_cam_pos.y)) + sin(time / 12.2)
    ) * distance;

    mat4 view_mat = view_matrix(cam_pos, vec3(0.0, 0.0, .0), vec3(0.0, 1.0, 0.0));
    vec3 v_dir = (view_mat * vec4(dir, 0.0)).xyz;

    gl_FragColor = render(cam_pos, v_dir);
}
