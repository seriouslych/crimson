shader_type spatial;

// Параметры Wave Texture 1
uniform float wave1_scale : hint_range(0.0, 100.0) = 4.0;
uniform float wave1_distortion : hint_range(0.0, 100.0) = 13.0;
uniform float wave1_detail : hint_range(0.0, 15.0) = 1.0;
uniform float wave1_detail_scale : hint_range(0.0, 10.0) = 1.0;
uniform float wave1_phase_offset : hint_range(0.0, 100.0) = 0.0;

// Параметры Wave Texture 2
uniform float wave2_scale : hint_range(0.0, 100.0) = 1.0;
uniform float wave2_distortion : hint_range(0.0, 100.0) = 0.0;
uniform float wave2_detail : hint_range(0.0, 15.0) = 13.0;
uniform float wave2_detail_scale : hint_range(0.0, 10.0) = 1.0;
uniform float wave2_phase_offset : hint_range(0.0, 100.0) = 0.0;

// Параметры ColorRamp 1
uniform float ramp1_pos : hint_range(0.0, 1.0) = 1.0;

// Параметры ColorRamp 2
uniform vec3 color_start : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_mid : source_color = vec3(0.0, 0.5, 1.0);
uniform vec3 color_end : source_color = vec3(1.0, 1.0, 1.0);
uniform float color_pos1 : hint_range(0.0, 1.0) = 0.0;
uniform float color_pos2 : hint_range(0.0, 1.0) = 0.6;
uniform float color_pos3 : hint_range(0.0, 1.0) = 1.0;

// Параметры Alpha
uniform float alpha_value : hint_range(0.0, 1.0) = 1.0;

// Параметры Bump
uniform float bump_strength : hint_range(0.0, 2.0) = 0.5;
uniform float bump_distance : hint_range(0.0, 0.1) = 0.01;

// Режим волн (для винила используем радиальный)
uniform bool use_radial_waves = true;
uniform float radial_frequency : hint_range(1.0, 100.0) = 30.0;

// ===== WAVE TEXTURE (РАДИАЛЬНАЯ ВЕРСИЯ) =====
float wave_texture_radial(vec2 uv, float scale, float distortion, float detail, float detail_scale, float phase) {
	// Конвертируем UV в полярные координаты
	vec2 centered = uv - vec2(0.5);
	float angle = atan(centered.y, centered.x);
	float radius = length(centered) * 2.0;
	
	// Базовая волна по радиусу (концентрические круги)
	float wave = sin(radius * scale * radial_frequency + phase);
	
	// Добавляем искажение по углу
	if (distortion > 0.0) {
		float angle_distort = sin(angle * 4.0) * distortion * 0.1;
		wave = sin((radius * scale * radial_frequency + angle_distort) + phase);
	}
	
	// Добавляем детализацию
	if (detail > 0.0) {
		for (float i = 1.0; i <= detail; i += 1.0) {
			float freq = pow(2.0, i) * detail_scale;
			float amp = 1.0 / pow(2.0, i);
			wave += sin(radius * scale * radial_frequency * freq + phase) * amp * 0.5;
		}
	}
	
	return (wave + 1.0) * 0.5;
}

// ===== COLOR RAMP =====
vec3 color_ramp(float factor) {
	factor = clamp(factor, 0.0, 1.0);
	
	if (factor <= color_pos1) {
		return color_start;
	} else if (factor <= color_pos2) {
		float t = (factor - color_pos1) / (color_pos2 - color_pos1);
		return mix(color_start, color_mid, t);
	} else if (factor <= color_pos3) {
		float t = (factor - color_pos2) / (color_pos3 - color_pos2);
		return mix(color_mid, color_end, t);
	}
	return color_end;
}

// ===== BUMP =====
vec3 calculate_normal(vec2 uv, float current_height) {
	float delta = bump_distance;
	
	float h_right = wave_texture_radial(uv + vec2(delta, 0.0), wave1_scale, wave1_distortion, wave1_detail, wave1_detail_scale, wave1_phase_offset);
	float h_left = wave_texture_radial(uv - vec2(delta, 0.0), wave1_scale, wave1_distortion, wave1_detail, wave1_detail_scale, wave1_phase_offset);
	float h_up = wave_texture_radial(uv + vec2(0.0, delta), wave1_scale, wave1_distortion, wave1_detail, wave1_detail_scale, wave1_phase_offset);
	float h_down = wave_texture_radial(uv - vec2(0.0, delta), wave1_scale, wave1_distortion, wave1_detail, wave1_detail_scale, wave1_phase_offset);
	
	vec3 gradient;
	gradient.x = (h_right - h_left) * bump_strength * 10.0;
	gradient.z = (h_up - h_down) * bump_strength * 10.0;
	gradient.y = 1.0;
	
	return normalize(gradient);
}

void fragment() {
	// ===== ГЕНЕРИРУЕМ ДВЕ ВОЛНОВЫЕ ТЕКСТУРЫ =====
	float wave1 = wave_texture_radial(UV, wave1_scale, wave1_distortion, wave1_detail, wave1_detail_scale, wave1_phase_offset);
	float wave2 = wave_texture_radial(UV, wave2_scale, wave2_distortion, wave2_detail, wave2_detail_scale, wave2_phase_offset);
	
	// ===== MIX =====
	float mix_factor = clamp(wave1 * ramp1_pos, 0.0, 1.0);
	float mixed_value = mix(wave1, wave2, mix_factor);
	
	// ===== COLOR RAMP =====
	vec3 final_color = color_ramp(mixed_value);
	
	// ===== ПРИМЕНЯЕМ =====
	ALBEDO = final_color;
	ALPHA = alpha_value;
	
	// ===== BUMP =====
	if (bump_strength > 0.0) {
		vec3 custom_normal = calculate_normal(UV, wave1);
		NORMAL = mix(NORMAL, custom_normal, bump_strength);
	}
	
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
}