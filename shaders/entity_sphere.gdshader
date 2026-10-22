shader_type canvas_item;

// Mesma iluminacao esferica do terreno (populous_planet.gdshader), aplicada
// aos sprites de unidades/construcoes/recursos para que eles participem do
// mesmo "planeta" e nao parecam flutuar fora do chao.
uniform float planet_radius : hint_range(0.2, 1.0) = 0.48;
uniform float planet_radius_world = 960.0;
uniform vec2 camera_offset = vec2(0.0);
uniform vec2 rect_size = vec2(2600.0);
uniform vec4 atmosphere_color : source_color = vec4(0.2, 0.55, 0.85, 0.4);
uniform vec2 entity_world_pos = vec2(0.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    if (tex.a < 0.01) {
        discard;
    }

    // Sem mais iluminacao "ancorada no mundo": o terreno e' um mapa toroidal
    // sem luz propria e a DirectionalLight3D sombreia a esfera. O sprite entra
    // no mesmo SubViewport do terreno, entao acompanha a rotacao do planeta e
    // recebe exatamente a mesma luz que o chao.
    COLOR = tex;
}