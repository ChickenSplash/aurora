#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float enabled;
    float gamma;
    vec4 tint0;
    vec4 tint1;
    vec4 tint2;
    vec4 tint3;
};
layout(binding = 1) uniform sampler2D source;

// Gradient map: HSB brightness (not luminance, so saturated red and blue detail
// survives), gamma, then four colour stops from dark to light
void main() {
    vec3 c = texture(source, qt_TexCoord0).rgb;
    float v = pow(max(c.r, max(c.g, c.b)), 1.0 / gamma);

    float s = clamp(v * 4.0 - 0.5, 0.0, 3.0);
    vec3 mapped = s < 1.0 ? mix(tint0.rgb, tint1.rgb, s)
                : s < 2.0 ? mix(tint1.rgb, tint2.rgb, s - 1.0)
                          : mix(tint2.rgb, tint3.rgb, s - 2.0);

    fragColor = vec4(mix(c, mapped, enabled), 1.0) * qt_Opacity;
}
