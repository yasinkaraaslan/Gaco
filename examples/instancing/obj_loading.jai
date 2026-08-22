WHITE :: Vector4.{1,1,1,1};

v3 :: make_vector3;
v4 :: make_vector4;

Vertex :: struct {
    position: Vector3;
    color: Vector4;
    normal: Vector3;
    uv: Vector2;
}

white_texture: Gaco.Texture;

operator == :: compare_vertex;

compare_vertex :: (v0: Vertex, v1: Vertex) -> bool {
    return v0.position == v1.position && v0.color == v1.color && v0.normal == v1.normal && v0.uv == v1.uv;
}

Mesh :: struct {
    vertex_buffer: Gaco.Buffer(.Vertex);
    index\_buffer: Gaco.Buffer(.Index);
    index_count: u32;
}

Obj_Model :: struct {
    name: string;
    textures: [4]Gaco.Texture;
    mesh: Mesh;
}

Texture_Map_Type :: enum u32 {
    Ambient;
    Diffuse;
    Specular;
    Normal;
}

load_obj :: (file_name: string) -> Obj_Model {
    short_name, texture_file_names, vertices, indices := parse_obj(file_name);

    model: Obj_Model;
    model.name = copy_string(short_name);
    for texture_file_names {
        if it {
            model.textures[it_index] = Gaco.create_texture_from_file(it, mip_levels=4, flags=.Generate_Mips | .Sampled);
        }
        else {
            model.textures[it_index] = white_texture;
        }
    }
    model.mesh.vertex_buffer = Gaco.create_buffer(vertices, .Vertex);
    model.mesh.index_buffer = Gaco.create_buffer(indices, .Index);
    model.mesh.index_count = indices.count.(u32);

    return model;
}

parse_obj :: (file_name: string) -> short_name: string, texture_file_names: []string, vertex_data: []Vertex, index_data: []u32 {
    push_allocator(temp);
    Obj_Load_Face_Data :: struct {
        pos_idx, uv_idx, normal_idx: u16;
        material_name: string;
    }

    handler := Text_File_Handler.{
        do_version_number = false,
    };
    short_name := path_basename(file_name);
    path_name := path_strip_filename(file_name);

    start_file(*handler, short_name, file_name);
    if handler.failed return "", .{}, .{}, .{};

    position_data: [..]Vector3;
    normal_data: [..]Vector3;
    uv_data: [..]Vector2;


    face_data: [..]Obj_Load_Face_Data;

    mtl_file_name: string;
    current_material_name: string;

    line_number := 0;
    while true {
        line, found := consume_next_line(*handler);
        if !found break;
        line_number += 1;

        left, right := break_by_spaces(line);

        if left == {
        case "mtllib";
            assert(!mtl_file_name);
            mtl_file_name = tprint("%/%", path_name, right);
        case "usemtl";
            current_material_name = right;
        case "g";
        case "v";
            pos: Vector3;
            extra: Vector3;
            ok := scan2(right, "% % % % % %", *pos.x, *pos.y, *pos.z, *extra.x, *extra.y, *extra.z);
            if !ok log_error("Error on line %: couldn't read position.", line_number);
            array_add(*position_data, pos);
        case "vt";
            uv: Vector2;
            ok := scan2(right, "% %", *uv.x, *uv.y);

            uv.y = 1 - uv.y;
            if !ok log_error("Error on line %: couldn't read texture coords.", line_number);
            array_add(*uv_data, uv);
        case "vn";
            normal: Vector3;
            ok := scan2(right, "% % %", *normal.x, *normal.y, *normal.z);
            if !ok log_error("Error on line %: couldn't read normal.", line_number);
            array_add(*normal_data, normal);
        case "f";
            faces: [3]Obj_Load_Face_Data;

            // Turn ccw to cw
            ok := scan2(right, "%/%/% %/%/% %/%/%",
                        *faces[0].pos_idx, *faces[0].uv_idx, *faces[0].normal_idx,
                        *faces[2].pos_idx, *faces[2].uv_idx, *faces[2].normal_idx,
                        *faces[1].pos_idx, *faces[1].uv_idx, *faces[1].normal_idx,
                        );
            if !ok log_error("Error on line %: couldn't read face. This is probably because we didn't implement the way this file is describing faces. We were trying to parse: %", line_number, right);

            for 0..2
                faces[it].material_name = current_material_name;
            array_add(*face_data, ..faces);

        }

    }

    texture_file_names, materials := parse_mtl(mtl_file_name);

    vertices: [..]Vertex;

    indices: [..]u32;

    find_material :: (material_name: string) -> *Obj_Material_Data #expand {
        for * materials {
            if material_name == it.name
                return it;
        }
        return null;
    }

    current_material: *Obj_Material_Data;
    for face_data {
        if !current_material || current_material.name != it.material_name {
            current_material = find_material(it.material_name);
        }

        vertex: Vertex;
        vertex.position = position_data[it.pos_idx - 1];
        vertex.color    = current_material.diffuse;
        vertex.normal   = normal_data[it.normal_idx - 1];
        vertex.uv       = uv_data[it.uv_idx - 1];

        found, index := array_find(vertices, vertex, compare_vertex);

        if !found {
            array_add(*vertices, vertex);
            array_add(*indices, cast(u16)vertices.count-1);
        }
        else {
            array_add(*indices, cast(u16)index);
        }
    }

    return short_name, texture_file_names, vertices, indices;
}

Obj_Material_Data :: struct {
    name: string;
    ambient := WHITE;
    diffuse := WHITE;
    specular := WHITE;
}

parse_mtl :: (file_name: string) -> texture_file_names: []string,  []Obj_Material_Data {
    push_allocator(temp);

    handler := Text_File_Handler.{
        do_version_number = false,
    };
    short_name := path_basename(file_name);
    path_name  := path_strip_filename(file_name);
    material: Obj_Material_Data;

    start_file(*handler, short_name, file_name);

    line_number := 0;

    texture_file_names := NewArray(4, string);
    materials: [..]Obj_Material_Data;

    current_material: *Obj_Material_Data;

    scan_color :: () -> Vector4 #expand {
        if current_material {
            color: Vector4;
            ok := scan2(`right, "% % %", *color.x, *color.y, *color.z);
            if ok {
                color.w = 1;
                return color;
            }
            else {
                log_error("Wasn't able to scan % at %:%", `left, `file_name, `line_number);
            }
        }
        else {
            log_error("Unexpected % at %:%", `left, `file_name, `line_number);
        }
        return .{};
    }

    while true {
        line, found := consume_next_line(*handler);
        if !found break;
        line_number += 1;

        left, right := break_by_spaces(line);

        if left == {
        case "newmtl";
            current_material = array_add(*materials);
            current_material.name = right;
        case "Ka";
            current_material.ambient = scan_color();
        case "Kd";
            current_material.diffuse = scan_color();
        case "Ks";
            current_material.specular = scan_color();
        case "map_Ka";
            texture_file_names[Texture_Map_Type.Ambient] = join(path_name, right);
        case "map_Kd";
            texture_file_names[Texture_Map_Type.Diffuse] = join(path_name, right);
        case "map_Ks";
            texture_file_names[Texture_Map_Type.Specular] = join(path_name, right);
        }
    }

    return texture_file_names, materials;
}

#import "Text_File_Handler";