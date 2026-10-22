shader_type canvas_item;
// Shader de DEPURACAO temporario: escreve na cor a posicao de mundo que o
// shader do terreno associa a cada pixel (sem ambiguidade: o mapa visivel tem
// menos de 1 periodo de world_size).
uniform vec2 camera_offset = vec2(0.0);
uniform vec2 world_size = vec2(2000.0);
uniform vec2 rect_size = vec2(2600.0);

void fragment() {
	vec2 world_px = camera_offset + (UV - vec2(0.5)) * rect_size;
	COLOR = vec4(fract(world_px / world_size), 0.0, 1.0);
}
