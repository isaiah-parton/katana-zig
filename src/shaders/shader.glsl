@header const math = @import("../math.zig")
@ctype vec2 math.Vec2

@vs vs
struct Shape_Spatial {
    vec2 quad_min;
    vec2 quad_max;
    vec2 tex_min;
    vec2 tex_max;
    uint xform;
};

struct Transform {
    mat4 matrix;
};

layout(binding = 0) uniform vs_params {
    vec2 screen_size;
};
layout(std430, binding = 0) readonly buffer shapesVertexBuffer
{
    Shape_Spatial vs_shapes[];
};
layout(std430, binding = 1) readonly buffer xformsBuffer
{
    Transform xforms[];
};

out vec2 p;
out vec2 uv;
flat out uint shape_idx;

void main() {
    Shape_Spatial shape = vs_shapes[gl_InstanceIndex];

    vec2 out_p;
    vec2 out_uv;

    if (gl_VertexIndex == 0u) {
        out_p = shape.quad_min;
        out_uv = shape.tex_min;
    } else if (gl_VertexIndex == 1u) {
        out_p = vec2(shape.quad_min.x, shape.quad_max.y);
        out_uv = vec2(shape.tex_min.x, shape.tex_max.y);
    } else if (gl_VertexIndex == 2u) {
        out_p = vec2(shape.quad_max.x, shape.quad_min.y);
        out_uv = vec2(shape.tex_max.x, shape.tex_min.y);
    } else if (gl_VertexIndex == 3u) {
        out_p = shape.quad_max;
        out_uv = shape.tex_max;
    }

    mat4 xform = xforms[shape.xform].matrix;
    vec2 pos = (xform * vec4(out_p, 0.0, 1.0)).xy;
    pos = vec2(2.0, -2.0) * pos / screen_size + vec2(-1.0, 1.0);

    gl_Position = vec4(pos, 0.0, 1.0);
    p = out_p;
    uv = out_uv;
    shape_idx = gl_InstanceIndex;
}
@end

@fs fs
struct Paint {
    uint kind;
    float noise;
    vec2 cv0;
    vec2 cv1;
    vec2 cv2;
    vec2 cv3;
    vec4 col0;
    vec4 col1;
    vec4 col2;
};
struct Shape {
    uint kind;
    uint next;
    vec2 cv0;
    vec2 cv1;
    vec2 cv2;
    vec4 radius;
    float width;
    uint start;
    uint count;
    uint stroke;
    uint paint;
    uint mode;
};
struct Vertex {
	vec2 pos;
};
layout(binding = 1) uniform fs_params {
    float time;
    float output_gamma;
    float text_unit_range;
    float text_in_bias;
    float text_out_bias;
};
layout(std430, binding = 2) readonly buffer shapesBuffer
{
    Shape shapes[];
};
layout(std430, binding = 3) readonly buffer paintsBuffer
{
    Paint paints[];
};
layout(std430, binding = 4) readonly buffer verticesBuffer
{
	Vertex vertices[];
};

layout(binding = 2) uniform texture2D msdf_texture;
layout(binding = 3) uniform sampler msdf_sampler;
layout(binding = 4) uniform texture2D paint_texture;
layout(binding = 5) uniform sampler paint_sampler;

in vec2 p;
in vec2 uv;
flat in uint shape_idx;

out vec4 frag_color;

// Math helpers
float dot2(vec2 v) {
    return dot(v, v);
}

vec3 not_vec3(bvec3 v) {
    return vec3(!v.x ? 1.0 : 0.0, !v.y ? 1.0 : 0.0, !v.z ? 1.0 : 0.0);
}

vec2 hash(vec2 p) {
    vec2 pp = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(pp) * 43758.5453123);
}

float random(vec2 coords) {
    return fract(sin(dot(coords.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float simplex_noise(vec2 p) {
    const float K1 = 0.366025404;
    const float K2 = 0.211324865;

    vec2 i = floor(p + (p.x + p.y) * K1);
    vec2 a = p - i + (i.x + i.y) * K2;
    float m = step(a.y, a.x);
    vec2 o = vec2(m, 1.0 - m);
    vec2 b = a - o + K2;
    vec2 c = a - 1.0 + 2.0 * K2;
    vec3 h = max(vec3(0.5) - vec3(dot2(a), dot2(b), dot2(c)), vec3(0.0));
    vec3 n = h * h * h * h * vec3(dot(a, hash(i + 0.0)), dot(b, hash(i + o)), dot(c, hash(i + 1.0)));
    return dot(n, vec3(70.0));
}

// Signed-distance functions
float sd_circle(vec2 p, float r) {
    return length(p) - r;
}

float sd_box(vec2 p, vec2 b, vec4 rr) {
    vec2 r;
    if (p.x > 0.0) {
        r = rr.yw;
    } else {
        r = rr.xz;
    }
    if (p.y > 0.0) {
        r.x = r.y;
    }
    vec2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r.x;
}

float cro(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

float det(vec2 a, vec2 b) {
    return a.x * b.y - b.x * a.y;
}

vec2 get_distance_vector(vec2 b0, vec2 b1, vec2 b2) {
    float a = det(b0, b2);
    float b = 2.0 * det(b1, b0);
    float d = 2.0 * det(b2, b1);

    float f = b * d - a * a;
    vec2 d21 = b2 - b1;
    vec2 d10 = b1 - b0;
    vec2 d20 = b2 - b0;
    vec2 gf = 2.0 * (b * d21 + d * d10 + a * d20);
    gf = vec2(gf.y, -gf.x);
    vec2 pp = -f * gf / dot(gf, gf);
    vec2 d0p = b0 - pp;
    float ap = det(d0p, d20);
    float bp = 2.0 * det(d10, d0p);
    float t = clamp((ap + bp) / (2.0 * a + b + d), 0.0, 1.0);
    return mix(mix(b0, b1, t), mix(b1, b2, t), t);
}

float sd_bezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
    vec2 a = B - A;
    vec2 b = A - 2.0 * B + C;
    vec2 c = a * 2.0;
    vec2 d = A - pos;
    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float res = 0.0;
    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p3;

    if (h > 0.0) {
        h = sqrt(h);
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.732050808;
        vec3 t = clamp(vec3(m + m, -n - m, n - m) * z - kx, vec3(0.0), vec3(1.0));
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}

float sd_line(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

bool test_bezier(vec2 p, vec2 A, vec2 B, vec2 C) {
	// Compute barycentric coordinates of p.
	// p = s * A + t * B + (1-s-t) * C
	vec2 v0 = B - A;
	vec2 v1 = C - A;
	vec2 v2 = p - A;
	float det = v0.x * v1.y - v1.x * v0.y;
	float s = (v2.x * v1.y - v1.x * v2.y) / det;
	float t = (v0.x * v2.y - v2.x * v0.y) / det;
	if(s < 0.0 || t < 0.0 || (1.0 - s - t) < 0.0) {
		return false; // outside triangle
	}
	// Transform to canonical coordinte space.
	float u = s / 2 + t;
	float v = t;
	return u * u < v;
}

bool test_line(vec2 p, vec2 A, vec2 B) {
	int cs = int(A.y < p.y) * 2 + int(B.y < p.y);
	if (cs == 0 || cs == 3) {
		return false;
	}
	vec2 v = B - A;
	float t = (p.y - A.y) / v.y;
	return (A.x + t * v.x) > p.x;
}

// Text rendering functions
float median(float r, float g, float b) {
	return max(min(r, g), min(max(r, g), b));
}

float screen_px_range(vec2 texcoord) {
	vec2 screen_tex_size = vec2(1.0) / fwidth(texcoord);
	return max(0.5 * dot(vec2(text_unit_range), screen_tex_size), 2.0);
}

float contour(float dist, float bias, vec2 texcoord) {
	float width = screen_px_range(texcoord);
	float e = width * (dist - 0.5 + text_in_bias) + 0.5 + (text_out_bias + bias);
	return smoothstep(0.0, 1.0, e);
}

float sample_msdf(vec2 uv, float bias) {
	vec3 msd = texture(sampler2D(msdf_texture, msdf_sampler), uv).rgb;
	float dist = median(msd.r, msd.g, msd.b);
	return contour(dist, bias, uv);
}

// HSL to RGB conversion
float hue_to_rgb(float p, float q, float tt) {
    float t = tt;
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * 6.0 * (2.0 / 3.0 - t);
    return p;
}

vec3 hsl_to_rgb(float h, float s, float l) {
    float r, g, b;
    if (s == 0.0) {
        r = g = b = l;
    } else {
        float q;
        if (l < 0.5) {
            q = l * (1.0 + s);
        } else {
            q = l + s - l * s;
        }
        float p = 2.0 * l - q;
        r = hue_to_rgb(p, q, h + 1.0 / 3.0);
        g = hue_to_rgb(p, q, h);
        b = hue_to_rgb(p, q, h - 1.0 / 3.0);
    }
    return vec3(r, g, b);
}

// Shape distance function (simplified - add more cases as needed)
float sd_shape(Shape shape, vec2 pos) {
    float d = 1e10;

    if (shape.kind == 1u) {
        // Circle
        d = sd_circle(pos - shape.cv0, shape.radius.x);
    } else if (shape.kind == 2u) {
        // Box
        vec2 center = 0.5 * (shape.cv0 + shape.cv1);
        d = sd_box(pos - center, (shape.cv1 - shape.cv0) * 0.5, shape.radius);
    } else if (shape.kind == 4u) {
        // Line segment
        d = sd_line(pos, shape.cv0, shape.cv1) - shape.width;
    } else if (shape.kind == 5u) {
        // Bezier
        d = sd_bezier(pos, shape.cv0, shape.cv1, shape.cv2) - shape.width;
    } else if (shape.kind == 6u) {
        // Path
        float s = 1.0;
        float filterWidth = 1.0;
        for (int i = 0; i < int(shape.count); i += 1) {
            int j = int(shape.start) + 3 * i;
            vec2 a = vertices[j].pos;
            vec2 b = vertices[j + 1].pos;
            vec2 c = vertices[j + 2].pos;
            bool skip = false;
            float xmax = p.x + filterWidth;
            float xmin = p.x - filterWidth;
            // If the hull is far enough away, don't bother with
            // an sdf.
            if (a.x > xmax && b.x > xmax && c.x > xmax) {
                skip = true;
            } else if (a.x < xmin && b.x < xmin && c.x < xmin) {
                skip = true;
            }
            if (!skip) {
                d = min(d, sd_bezier(p, a, b, c));
            }
            if (test_line(p, a, c)) {
                s = -s;
            }
            // Flip if inside area between curve and line.
            if (!skip) {
                if (test_bezier(p, a, b, c)) {
                    s = -s;
                }
            }
        }
        d = d * s;
    } else if (shape.kind == 7u) {
    	// MSDF
    	// Supersampling parameters
    	float dscale = 0.354;
      	float bias = shape.radius[0];
		vec2 duv = dscale * (dFdxFine(uv) + dFdyFine(uv));
		vec4 box = vec4(uv - duv, uv + duv);
		// Supersample the sdf texture
		float asum = sample_msdf(box.xy, bias) + sample_msdf(box.zw, bias) + sample_msdf(box.xw, bias) + sample_msdf(box.zy, bias);
		// Determine opacity
		float alpha = (sample_msdf(uv, bias) + 0.5 * asum) / 3.0;
		// Reflect opacity with distance result
		d = 0.5 - alpha;
    }

    // Stroke handling
    if (shape.stroke == 1u) {
        float r = shape.width * 0.5;
        d = abs(d + r) - r;
    } else if (shape.stroke == 2u) {
        d = abs(d) - shape.width / 2.0;
    } else if (shape.stroke == 3u) {
        float r = shape.width * 0.5;
        d = abs(d - r) - r;
    }

    if (shape.stroke > 0u && shape.width < 0.5) {
        d = 0.5;
    }

    return d;
}

float smin(float a, float b, float k) {
    float r = exp2(-a / k) + exp2(-b / k);
    return -k * log2(r);
}

void main() {
    vec4 out_color = vec4(0.0);
    float d = 0.0;

    Shape shape = shapes[shape_idx];

    if (shape.paint == 0u) {
        discard;
    }

    Paint paint = paints[shape.paint];

    if (shape.kind > 0u) {
        d = sd_shape(shape, p);
    }

    // Handle chained shapes
    while (shape.next > 0u) {
        shape = shapes[shape.next];
        if (shape.kind > 0u) {
            if (shape.mode == 0u) {
                // Union
                d = smin(d, sd_shape(shape, p), 1.5);
            } else if (shape.mode == 1u) {
                // Subtraction
                d = max(-d, sd_shape(shape, p));
            } else if (shape.mode == 2u) {
                // Intersection
                d = max(d, sd_shape(shape, p));
            }
        }
    }

    float antialias_threshold = 0.5;
    float opacity = clamp(antialias_threshold - d, 0.0, 1.0);

    if (opacity == 0.0) {
        discard;
    }

    // Paint types
    if (paint.kind == 1u) {
        // Solid color
        out_color = paint.col0;
    } else if (paint.kind == 2u) {
    	// Image
     	out_color = texture(sampler2D(paint_texture, paint_sampler), uv) * paint.col0;
    } else if (paint.kind == 5u) {
        // Linear gradient
        vec2 dir = paint.cv1 - paint.cv0;
        float det = 1.0 / ((dir.x * dir.x) - (-dir.y * dir.y));
        mat2 xform = mat2(det * dir.x, det * dir.y, det * -dir.y, det * dir.x);
        float t = clamp((xform * (p - paint.cv0)).x, 0.0, 1.0);
        out_color = mix(paint.col0, paint.col1, t + mix(-paint.noise, paint.noise, random(p)));
    } else if (paint.kind == 6u) {
        // Radial gradient
        float r = paint.cv1.x;
        float t = clamp(length(p - paint.cv0) / r, 0.0, 1.0);
        out_color = mix(paint.col0, paint.col1, t + mix(-paint.noise, paint.noise, random(p)));
    }

    out_color = vec4(pow(abs(out_color.rgb), vec3(output_gamma)), out_color.a * opacity);
    frag_color = out_color;
}
@end

@program shader vs fs
