#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float wave;
    float flicker;
    float bass;
    float mid;
    float treble;
    float load;
    float aspect;
    vec4 colA;
    vec4 colB;
    vec4 colC;
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time;

    // Slow flow field warps the wallpaper; bass pushes it harder
    vec2 q = vec2(fbm(p * 2.0 + t * 0.03), fbm(p * 2.0 - t * 0.025 + 5.2));
    vec2 warp = (q - 0.5) * (0.006 + bass * 0.018);
    vec3 base = texture(source, uv + warp).rgb;

    // Aurora curtains: a meandering ribbon with a sharp lower edge and rays
    // fading upwards, broken into patches along its length. Lit by mids.
    vec3 aurora = vec3(0.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float x = p.x + fi * 2.7;
        float edge = 0.34 + fi * 0.08
            + 0.09 * sin(x * 2.3 + wave * 0.07 + fi * 2.0)
            + 0.05 * sin(x * 5.1 - wave * 0.11 + fi)
            + 0.22 * (fbm(vec2(x * 0.8, wave * 0.04 + fi * 5.0)) - 0.5)
            - 0.10 * (uv.x - 0.5);
        float h = edge - uv.y;

        float height = (0.10 + 0.14 * noise(vec2(x * 1.7, wave * 0.05))) * (1.0 + bass * 0.6) * (1.0 - fi * 0.2);
        float curtain = h < 0.0 ? exp(h * 45.0) : exp(-h / height);

        // Rays lean slightly and follow the fold, so they are not vertical bars
        float rx = x * 55.0 + h * 12.0 + fbm(vec2(x * 3.0, wave * 0.1)) * 6.0;
        float rays = 0.35 + 0.65 * pow(noise(vec2(rx, fi * 7.0)), 1.5);
        rays *= 0.7 + 0.3 * noise(vec2(rx * 0.25, h * 6.0));
        // Gentle treble shimmer, at most a quarter of the ray brightness
        rays *= 1.0 - min(treble, 1.0) * 0.25 * noise(vec2(rx * 0.7, flicker));

        float patches = smoothstep(0.35, 0.75, fbm(vec2(x * 0.9 - wave * 0.03, fi * 3.3)));

        vec3 c = mix(colA.rgb, fi == 1.0 ? colB.rgb : colC.rgb, smoothstep(0.0, height * 2.5, h));
        c += c * 0.6 * exp(-abs(h) * 35.0);
        aurora += c * curtain * rays * patches * (1.0 - fi * 0.3);
    }
    aurora *= 0.12 + mid * 0.9 + load * 0.15;

    // Bass glow rising from the bottom centre
    float r = length(vec2((uv.x - 0.5) * aspect, (uv.y - 1.15) * 1.6));
    vec3 glow = colA.rgb * exp(-r * 2.2) * bass * bass * 0.9;

    vec3 fx = aurora + glow;
    vec3 col = base + fx * (1.0 - base * 0.6);

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
