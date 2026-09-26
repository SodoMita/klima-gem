#include "gdextension_interface.h"
#include "audio_gen.h"

#include <string.h>
#include <stdlib.h>

#if defined(_WIN32)
#define AG_EXPORT __declspec(dllexport)
#else
#define AG_EXPORT __attribute__((visibility("default")))
#endif

typedef struct { uint8_t data[16]; } NameBuf;
typedef struct { uint8_t data[24]; } VarBuf;

static struct {
    GDExtensionInterfaceGetGodotVersion2 get_godot_version2;
    GDExtensionInterfaceMemAlloc mem_alloc;
    GDExtensionInterfaceMemFree mem_free;
    GDExtensionInterfacePrintError print_error;
    GDExtensionInterfaceClassdbRegisterExtensionClass6 classdb_register_extension_class6;
    GDExtensionInterfaceClassdbUnregisterExtensionClass classdb_unregister_extension_class;
    GDExtensionInterfaceClassdbRegisterExtensionClassMethod classdb_register_extension_class_method;
    GDExtensionInterfaceClassdbConstructObject3 classdb_construct_object3;
    GDExtensionInterfaceObjectSetInstance object_set_instance;
    GDExtensionInterfaceStringNameNewWithUtf8Chars string_name_new_with_utf8_chars;
    GDExtensionInterfaceStringNewWithUtf8Chars string_new_with_utf8_chars;
    GDExtensionInterfaceVariantNewNil variant_new_nil;
    GDExtensionInterfaceVariantDestroy variant_destroy;
    GDExtensionInterfaceVariantGetType variant_get_type;
    GDExtensionInterfaceVariantCall variant_call;
    GDExtensionInterfaceGetVariantFromTypeConstructor get_variant_from_type_constructor;
    GDExtensionInterfaceGetVariantToTypeConstructor get_variant_to_type_constructor;
    GDExtensionVariantGetInternalPtrFunc packed_f32_ptr;
    GDExtensionVariantGetInternalPtrFunc packed_v2_ptr;
    GDExtensionVariantGetInternalPtrFunc packed_i32_ptr;
    GDExtensionInterfacePackedFloat32ArrayOperatorIndex packed_f32_op;
    GDExtensionInterfacePackedVector2ArrayOperatorIndex packed_v2_op;
    GDExtensionInterfacePackedInt32ArrayOperatorIndex packed_i32_op;
    GDExtensionVariantFromTypeConstructorFunc from_bool;
    GDExtensionVariantFromTypeConstructorFunc from_int;
    GDExtensionVariantFromTypeConstructorFunc from_float;
    GDExtensionTypeFromVariantConstructorFunc to_int;
    GDExtensionTypeFromVariantConstructorFunc to_float;
    GDExtensionTypeFromVariantConstructorFunc to_bool;
} api;

static GDExtensionClassLibraryPtr lib_ptr;
static NameBuf sn_class;
static NameBuf sn_parent;
static NameBuf sn_empty;
static NameBuf sn_size;
static NameBuf sn_render_sfx;
static NameBuf sn_render_drum;
static NameBuf sn_render_fm;
static NameBuf sn_render_proc;
static NameBuf sn_mood;
static NameBuf sn_root;
static NameBuf sn_bpm;
static NameBuf sn_seed;
static NameBuf sn_frames;
static NameBuf sn_gain;
static NameBuf sn_type;
static NameBuf sn_preset;
static NameBuf sn_freq;
static NameBuf sn_vel;
static NameBuf sn_biome;
static NameBuf sn_weather;
static NameBuf sn_intensity;
static NameBuf sn_tod;
static NameBuf sn_pos;
static NameBuf sn_forward;
static NameBuf sn_up;
static NameBuf sn_amb_class;
static NameBuf sn_amb_render;
static NameBuf sn_amb_set_biome;
static NameBuf sn_amb_set_weather;
static NameBuf sn_amb_set_listener;
static NameBuf sn_amb_set_gain;
static NameBuf sn_amb_add_source;
static NameBuf sn_min_dist;
static NameBuf sn_max_dist;
static NameBuf empty_string;
static int registered=0;
static int registered_amb=0;

static void make_name(NameBuf *n, const char *t) { memset(n,0,sizeof(*n)); api.string_name_new_with_utf8_chars(n,t); }
static void make_string(NameBuf *n, const char *t) { memset(n,0,sizeof(*n)); api.string_new_with_utf8_chars(n,t); }
static void set_ok(GDExtensionCallError *e) { if(e){ e->error=GDEXTENSION_CALL_OK; e->argument=0; e->expected=0; } }
static void return_nil(GDExtensionVariantPtr r, GDExtensionCallError *e){ api.variant_new_nil(r); set_ok(e); }

static int64_t call_size(GDExtensionConstVariantPtr packed) {
    VarBuf ret; GDExtensionCallError err; memset(&err,0,sizeof(err));
    api.variant_call((GDExtensionVariantPtr)packed, &sn_size, 0,0, &ret, &err);
    int64_t c=-1;
    if(err.error==GDEXTENSION_CALL_OK){ api.to_int(&c,&ret); api.variant_destroy(&ret); }
    return c;
}
static double read_float_arg(GDExtensionConstVariantPtr v) {
    if (api.variant_get_type(v)==GDEXTENSION_VARIANT_TYPE_INT) { int64_t i=0; api.to_int(&i,(GDExtensionVariantPtr)v); return (double)i; }
    if (api.variant_get_type(v)==GDEXTENSION_VARIANT_TYPE_FLOAT) { double d=0; api.to_float(&d,(GDExtensionVariantPtr)v); return d; }
    return 0.0;
}
static int64_t read_int_arg(GDExtensionConstVariantPtr v) {
    if (api.variant_get_type(v)==GDEXTENSION_VARIANT_TYPE_INT) { int64_t i=0; api.to_int(&i,(GDExtensionVariantPtr)v); return i; }
    if (api.variant_get_type(v)==GDEXTENSION_VARIANT_TYPE_FLOAT) { return (int64_t)read_float_arg(v); }
    return 0;
}
static int read_string(GDExtensionConstVariantPtr v, char *out, int cap);

/* Wrapper instance: holds a proc mixer for live use */
typedef struct AgGDE {
    AgProcMixer mixer;
    AgRng rng;
    int sr;
} AgGDE;

typedef struct AgAmbienceGDE {
    AgAmbience3D amb;
    int sr;
} AgAmbienceGDE;

static GDExtensionObjectPtr create_instance(void *userdata, GDExtensionBool notify) {
    (void)userdata; (void)notify;
    AgGDE *g = (AgGDE*)api.mem_alloc(sizeof(AgGDE));
    if(!g) return 0;
    memset(g,0,sizeof(*g));
    g->sr = 44100;
    ag_proc_mixer_init(&g->mixer, g->sr);
    ag_rng_seed(&g->rng, 1);
    GDExtensionObjectPtr obj = api.classdb_construct_object3(&sn_parent);
    if(!obj){ api.mem_free(g); return 0; }
    api.object_set_instance(obj, &sn_class, g);
    return obj;
}
static void free_instance(void *userdata, GDExtensionClassInstancePtr inst) {
    (void)userdata;
    if(inst){
        AgGDE *g = (AgGDE*)inst;
        for(int i=0;i<AG_PROC_LAYERS;i++){
            ag_reverb_free(&g->mixer.layers[i].reverb);
            ag_delay_free(&g->mixer.layers[i].delay);
        }
        api.mem_free(inst);
    }
}
static GDExtensionObjectPtr create_amb_instance(void *userdata, GDExtensionBool notify) {
    (void)userdata; (void)notify;
    AgAmbienceGDE *g = (AgAmbienceGDE*)api.mem_alloc(sizeof(AgAmbienceGDE));
    if(!g) return 0;
    memset(g,0,sizeof(*g));
    g->sr=44100;
    ag_ambience_3d_init(&g->amb, g->sr, ag_vec3(0,0,0));
    ag_ambience_3d_preset_forest(&g->amb);
    GDExtensionObjectPtr obj = api.classdb_construct_object3(&sn_parent);
    if(!obj){ api.mem_free(g); return 0; }
    api.object_set_instance(obj, &sn_amb_class, g);
    return obj;
}
static void free_amb_instance(void *userdata, GDExtensionClassInstancePtr inst) {
    (void)userdata;
    if(inst){
        AgAmbienceGDE *g = (AgAmbienceGDE*)inst;
        ag_reverb_free(&g->amb.reverb);
        api.mem_free(inst);
    }
}

/* Helper to render into PackedVector2Array */
static void render_into_packed_v2(AgGDE *gde, GDExtensionConstVariantPtr packed, int (*render_fn)(AgGDE*, float*, int)) {
    if (api.variant_get_type(packed)!=GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY) return;
    int64_t frames = call_size(packed);
    if(frames<=0) return;
    void *arr = api.packed_v2_ptr((GDExtensionVariantPtr)packed);
    float *base = (float*)api.packed_v2_op(arr,0);
    int contiguous = 0;
    if(frames>=2){
        float *second = (float*)api.packed_v2_op(arr,1);
        contiguous = second == base+2;
    } else contiguous=1;
    if(contiguous){
        render_fn(gde, base, (int)frames);
    } else {
        float *tmp = (float*)api.mem_alloc(sizeof(float)*frames*2);
        if(!tmp) return;
        render_fn(gde, tmp, (int)frames);
        for(int64_t i=0;i<frames;i++){
            float *slot = (float*)api.packed_v2_op(arr,i);
            if(slot){ slot[0]=tmp[i*2]; slot[1]=tmp[i*2+1]; }
        }
        api.mem_free(tmp);
    }
}

/* SFX render: expects args[0]=type string (coin,laser,etc), args[1]=frames PackedVector2Array */
static void m_render_sfx(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<2){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=2; } return; }
    /* For simplicity, we ignore string type and use coin if not recognized; future: parse string */
    int64_t frames = call_size(args[1]);
    if(frames<=0){ return_nil(ret,err); return; }
    /* We need to read type if it's int, else default */
    int type = 0;
    if(api.variant_get_type(args[0])==GDEXTENSION_VARIANT_TYPE_INT) type = (int)read_int_arg(args[0]);
    else if(api.variant_get_type(args[0])==GDEXTENSION_VARIANT_TYPE_STRING) {
        char buf[32]; if(read_string(args[0],buf,sizeof(buf))){
            if(strcmp(buf,"laser")==0) type=1;
            else if(strcmp(buf,"explosion")==0) type=2;
            else if(strcmp(buf,"powerup")==0) type=3;
            else if(strcmp(buf,"hit")==0) type=4;
            else if(strcmp(buf,"jump")==0) type=5;
            else if(strcmp(buf,"blip")==0) type=6;
        }
    }
    AgSfxParams sp;
    switch(type){
        case 1: ag_sfx_preset_laser(&sp); break;
        case 2: ag_sfx_preset_explosion(&sp); break;
        case 3: ag_sfx_preset_powerup(&sp); break;
        case 4: ag_sfx_preset_hit(&sp); break;
        case 5: ag_sfx_preset_jump(&sp); break;
        case 6: ag_sfx_preset_blip(&sp); break;
        default: ag_sfx_preset_coin(&sp); break;
    }
    void *arr = api.packed_v2_ptr((GDExtensionVariantPtr)args[1]);
    int64_t n = frames;
    float *base = (float*)api.packed_v2_op(arr,0);
    int contiguous = 0;
    if(n>=2){ float *second=(float*)api.packed_v2_op(arr,1); contiguous = second==base+2; } else contiguous=1;
    if(contiguous){
        /* render mono then duplicate */
        float *tmp = (float*)api.mem_alloc(sizeof(float)*n);
        if(tmp){
            ag_sfx_render(&sp, tmp, (int)n, 44100);
            for(int64_t i=0;i<n;i++){ base[i*2]=tmp[i]; base[i*2+1]=tmp[i]; }
            api.mem_free(tmp);
        }
    } else {
        for(int64_t i=0;i<n;i++){
            float *slot=(float*)api.packed_v2_op(arr,i);
            if(!slot) continue;
            /* we would need per-sample render; for simplicity render chunk */
            /* fallback: render one by one using voice */
            /* not efficient but works */
            slot[0]=0; slot[1]=0;
        }
        /* proper path would use temp buffer */
        float *tmp = (float*)api.mem_alloc(sizeof(float)*n);
        if(tmp){
            ag_sfx_render(&sp, tmp, (int)n, 44100);
            for(int64_t i=0;i<n;i++){
                float *slot=(float*)api.packed_v2_op(arr,i);
                if(slot){ slot[0]=tmp[i]; slot[1]=tmp[i]; }
            }
            api.mem_free(tmp);
        }
    }
    return_nil(ret,err);
}

static void m_render_drum(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata; (void)inst;
    if(argc<2){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=2; } return; }
    int type = (int)read_int_arg(args[0]);
    if(type<0) type=0; if(type>=AG_DRUM_COUNT) type=0;
    void *arr = api.packed_v2_ptr((GDExtensionVariantPtr)args[1]);
    int64_t n = call_size(args[1]);
    if(n<=0){ return_nil(ret,err); return; }
    AgDrumParams dp; ag_drum_params_default(&dp, (AgDrumType)type);
    float *tmp = (float*)api.mem_alloc(sizeof(float)*n);
    if(tmp){
        ag_drum_render(&dp, tmp, (int)n, 44100);
        for(int64_t i=0;i<n;i++){
            float *slot=(float*)api.packed_v2_op(arr,i);
            if(slot){ slot[0]=tmp[i]; slot[1]=tmp[i]; }
        }
        api.mem_free(tmp);
    }
    return_nil(ret,err);
}

static void m_render_fm(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata; (void)inst;
    if(argc<2){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=2; } return; }
    int preset = (int)read_int_arg(args[0]);
    double freq = 110.0;
    if(argc>=3) freq = read_float_arg(args[2]);
    void *arr = api.packed_v2_ptr((GDExtensionVariantPtr)args[1]);
    int64_t n = call_size(args[1]);
    if(n<=0){ return_nil(ret,err); return; }
    AgFmVoice2 v; ag_fm_voice2_init(&v, 44100, (float)freq, 2.0f);
    if(preset<0) preset=0; if(preset>=AG_FM_PRESET_COUNT) preset=0;
    ag_fm_apply_preset_2op(&v, (AgFmPreset)preset);
    ag_fm_voice2_note_on(&v, (float)freq, 0.8f);
    int half = (int)n/2;
    float *tmp = (float*)api.mem_alloc(sizeof(float)*n);
    if(tmp){
        for(int64_t i=0;i<n;i++){
            if(i==half) ag_fm_voice2_note_off(&v);
            tmp[i]=ag_fm_voice2_next(&v);
        }
        for(int64_t i=0;i<n;i++){
            float *slot=(float*)api.packed_v2_op(arr,i);
            if(slot){ slot[0]=tmp[i]; slot[1]=tmp[i]; }
        }
        api.mem_free(tmp);
    }
    return_nil(ret,err);
}

static int read_string(GDExtensionConstVariantPtr v, char *out, int cap) {
    /* Use variant_call to get utf8? Simplified: we will try to get via to_string? For now, not fully implemented.
       Godot String to utf8 requires more API; we approximate by not supporting string in this minimal wrapper,
       but we have int path. So return 0. */
    (void)v; (void)out; (void)cap;
    return 0;
}

static void m_render_proc(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<1){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=1; } return; }
    AgGDE *gde = (AgGDE*)inst;
    void *arr = api.packed_v2_ptr((GDExtensionVariantPtr)args[0]);
    int64_t n = call_size(args[0]);
    if(n<=0){ return_nil(ret,err); return; }
    float *base = (float*)api.packed_v2_op(arr,0);
    int contiguous=0;
    if(n>=2){ float *second=(float*)api.packed_v2_op(arr,1); contiguous = second==base+2; } else contiguous=1;
    if(contiguous){
        ag_proc_mixer_render(&gde->mixer, base, (int)n);
    } else {
        float *tmp=(float*)api.mem_alloc(sizeof(float)*n*2);
        if(tmp){
            ag_proc_mixer_render(&gde->mixer, tmp, (int)n);
            for(int64_t i=0;i<n;i++){
                float *slot=(float*)api.packed_v2_op(arr,i);
                if(slot){ slot[0]=tmp[i*2]; slot[1]=tmp[i*2+1]; }
            }
            api.mem_free(tmp);
        }
    }
    return_nil(ret,err);
}

static void m_transition(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<4){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=4; } return; }
    AgGDE *gde = (AgGDE*)inst;
    int mood = (int)read_int_arg(args[0]);
    double root = read_float_arg(args[1]);
    double bpm = read_float_arg(args[2]);
    double fade = read_float_arg(args[3]);
    AgProcSpec spec;
    ag_proc_spec_from_mood(&spec, (AgMood)mood, (int)root, (float)bpm, (uint64_t)ag_rng_next_u64(&gde->rng));
    spec.id = (uint64_t)(ag_rng_next_u64(&gde->rng) & 0xFFFFFFFF);
    ag_proc_mixer_transition(&gde->mixer, &spec, (float)fade);
    return_nil(ret,err);
}

/* Ambience3D methods */
static void m_amb_render(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<1){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=1; } return; }
    AgAmbienceGDE *gde = (AgAmbienceGDE*)inst;
    void *arr = api.packed_v2_ptr((GDExtensionVariantPtr)args[0]);
    int64_t n = call_size(args[0]);
    if(n<=0){ return_nil(ret,err); return; }
    float *base = (float*)api.packed_v2_op(arr,0);
    int contiguous=0;
    if(n>=2){ float *second=(float*)api.packed_v2_op(arr,1); contiguous = second==base+2; } else contiguous=1;
    if(contiguous){
        ag_ambience_3d_render(&gde->amb, base, (int)n);
    } else {
        float *tmp=(float*)api.mem_alloc(sizeof(float)*n*2);
        if(tmp){
            ag_ambience_3d_render(&gde->amb, tmp, (int)n);
            for(int64_t i=0;i<n;i++){
                float *slot=(float*)api.packed_v2_op(arr,i);
                if(slot){ slot[0]=tmp[i*2]; slot[1]=tmp[i*2+1]; }
            }
            api.mem_free(tmp);
        }
    }
    return_nil(ret,err);
}
static void m_amb_set_biome(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<3){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=3; } return; }
    AgAmbienceGDE *gde = (AgAmbienceGDE*)inst;
    int biome = (int)read_int_arg(args[0]);
    double tod = read_float_arg(args[1]);
    double weather = read_float_arg(args[2]);
    if(biome<0) biome=0; if(biome>=AG_BIOME_COUNT) biome=0;
    ag_ambience_3d_set_biome(&gde->amb, (AgBiomeType)biome, (float)tod, (float)weather);
    return_nil(ret,err);
}
static void m_amb_set_weather(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<2){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=2; } return; }
    AgAmbienceGDE *gde = (AgAmbienceGDE*)inst;
    int wtype = (int)read_int_arg(args[0]);
    double intens = read_float_arg(args[1]);
    if(wtype<0) wtype=0; if(wtype>=AG_WEATHER_COUNT) wtype=0;
    ag_ambience_3d_set_weather(&gde->amb, (AgWeatherType)wtype, (float)intens);
    return_nil(ret,err);
}
static void m_amb_set_gain(void *userdata, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)userdata;
    if(!inst || argc<1){ api.variant_new_nil(ret); if(err){ err->error=GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->argument=argc; err->expected=1; } return; }
    AgAmbienceGDE *gde = (AgAmbienceGDE*)inst;
    double gain = read_float_arg(args[0]);
    double fade = 0.5;
    if(argc>=2) fade = read_float_arg(args[1]);
    ag_ambience_3d_set_master_gain(&gde->amb, (float)gain, (float)fade);
    return_nil(ret,err);
}

static void bind_method(const NameBuf *name, GDExtensionClassMethodCall call, GDExtensionVariantType ret_type, int has_ret, const GDExtensionVariantType *arg_types, const NameBuf *const *arg_names, uint32_t argc) {
    GDExtensionPropertyInfo args[4]; GDExtensionClassMethodArgumentMetadata meta[4];
    GDExtensionPropertyInfo ret_info; GDExtensionClassMethodInfo info;
    memset(&info,0,sizeof(info)); memset(args,0,sizeof(args)); memset(&ret_info,0,sizeof(ret_info));
    for(uint32_t i=0;i<argc && i<4;i++){
        args[i].type=arg_types[i];
        args[i].name=(GDExtensionStringNamePtr)arg_names[i];
        args[i].class_name=&sn_empty;
        args[i].hint=0;
        args[i].hint_string=&empty_string;
        args[i].usage=6;
        if(arg_types[i]==GDEXTENSION_VARIANT_TYPE_INT) meta[i]=GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
        else if(arg_types[i]==GDEXTENSION_VARIANT_TYPE_FLOAT) meta[i]=GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE;
        else meta[i]=GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    }
    if(has_ret){
        ret_info.type=ret_type;
        ret_info.name=&sn_empty;
        ret_info.class_name=&sn_empty;
        ret_info.hint_string=&empty_string;
        ret_info.usage=6;
    }
    info.name=(GDExtensionStringNamePtr)name;
    info.method_userdata=0;
    info.call_func=call;
    info.ptrcall_func=0;
    info.method_flags=GDEXTENSION_METHOD_FLAGS_DEFAULT;
    info.has_return_value=has_ret?1:0;
    info.return_value_info=has_ret?&ret_info:0;
    info.return_value_metadata=has_ret && ret_type==GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    info.argument_count=argc;
    info.arguments_info=argc?args:0;
    info.arguments_metadata=argc?meta:0;
    info.default_argument_count=0;
    info.default_arguments=0;
    api.classdb_register_extension_class_method(lib_ptr, &sn_class, &info);
}

static void bind_method_amb(const NameBuf *name, GDExtensionClassMethodCall call, GDExtensionVariantType ret_type, int has_ret, const GDExtensionVariantType *arg_types, const NameBuf *const *arg_names, uint32_t argc) {
    GDExtensionPropertyInfo args[4]; GDExtensionClassMethodArgumentMetadata meta[4];
    GDExtensionPropertyInfo ret_info; GDExtensionClassMethodInfo info;
    memset(&info,0,sizeof(info)); memset(args,0,sizeof(args)); memset(&ret_info,0,sizeof(ret_info));
    for(uint32_t i=0;i<argc && i<4;i++){
        args[i].type=arg_types[i];
        args[i].name=(GDExtensionStringNamePtr)arg_names[i];
        args[i].class_name=&sn_empty;
        args[i].hint=0;
        args[i].hint_string=&empty_string;
        args[i].usage=6;
        if(arg_types[i]==GDEXTENSION_VARIANT_TYPE_INT) meta[i]=GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
        else if(arg_types[i]==GDEXTENSION_VARIANT_TYPE_FLOAT) meta[i]=GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE;
        else meta[i]=GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    }
    if(has_ret){
        ret_info.type=ret_type;
        ret_info.name=&sn_empty;
        ret_info.class_name=&sn_empty;
        ret_info.hint_string=&empty_string;
        ret_info.usage=6;
    }
    info.name=(GDExtensionStringNamePtr)name;
    info.method_userdata=0;
    info.call_func=call;
    info.ptrcall_func=0;
    info.method_flags=GDEXTENSION_METHOD_FLAGS_DEFAULT;
    info.has_return_value=has_ret?1:0;
    info.return_value_info=has_ret?&ret_info:0;
    info.return_value_metadata=has_ret && ret_type==GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    info.argument_count=argc;
    info.arguments_info=argc?args:0;
    info.arguments_metadata=argc?meta:0;
    info.default_argument_count=0;
    info.default_arguments=0;
    api.classdb_register_extension_class_method(lib_ptr, &sn_amb_class, &info);
}

static void register_class(void) {
    GDExtensionClassCreationInfo6 info; memset(&info,0,sizeof(info));
    if(registered && registered_amb) return;
    make_name(&sn_class,"AudioGen");
    make_name(&sn_amb_class,"Ambience3D");
    make_name(&sn_parent,"RefCounted");
    make_name(&sn_empty,"");
    make_name(&sn_size,"size");
    make_name(&sn_render_sfx,"render_sfx");
    make_name(&sn_render_drum,"render_drum");
    make_name(&sn_render_fm,"render_fm");
    make_name(&sn_render_proc,"render_proc");
    make_name(&sn_mood,"mood");
    make_name(&sn_root,"root");
    make_name(&sn_bpm,"bpm");
    make_name(&sn_seed,"seed");
    make_name(&sn_frames,"frames");
    make_name(&sn_gain,"gain");
    make_name(&sn_type,"type");
    make_name(&sn_preset,"preset");
    make_name(&sn_freq,"freq");
    make_name(&sn_vel,"vel");
    make_name(&sn_biome,"biome");
    make_name(&sn_weather,"weather");
    make_name(&sn_intensity,"intensity");
    make_name(&sn_tod,"time_of_day");
    make_name(&sn_pos,"pos");
    make_name(&sn_forward,"forward");
    make_name(&sn_up,"up");
    make_name(&sn_amb_render,"render_ambience");
    make_name(&sn_amb_set_biome,"set_biome");
    make_name(&sn_amb_set_weather,"set_weather");
    make_name(&sn_amb_set_listener,"set_listener");
    make_name(&sn_amb_set_gain,"set_gain");
    make_name(&sn_amb_add_source,"add_point_source");
    make_name(&sn_min_dist,"min_dist");
    make_name(&sn_max_dist,"max_dist");
    make_string(&empty_string,"");

    if(!registered){
        info.is_exposed=1;
        info.create_instance_func=create_instance;
        info.free_instance_func=free_instance;
        api.classdb_register_extension_class6(lib_ptr, &sn_class, &sn_parent, &info);

        GDExtensionVariantType t_v2[1]={GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY};
        const NameBuf *n_frames[1]={&sn_frames};
        GDExtensionVariantType t_int_v2[2]={GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY};
        const NameBuf *n_type_frames[2]={&sn_type,&sn_frames};
        GDExtensionVariantType t_int_v2_float[3]={GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, GDEXTENSION_VARIANT_TYPE_FLOAT};
        const NameBuf *n_preset_frames_freq[3]={&sn_preset,&sn_frames,&sn_freq};
        GDExtensionVariantType t_mood_root_bpm_fade[4]={GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT};
        const NameBuf *n_mood_root_bpm_fade[4]={&sn_mood,&sn_root,&sn_bpm,&sn_gain};

        bind_method(&sn_render_sfx, m_render_sfx, GDEXTENSION_VARIANT_TYPE_NIL,0, t_int_v2, n_type_frames,2);
        bind_method(&sn_render_drum, m_render_drum, GDEXTENSION_VARIANT_TYPE_NIL,0, t_int_v2, n_type_frames,2);
        bind_method(&sn_render_fm, m_render_fm, GDEXTENSION_VARIANT_TYPE_NIL,0, t_int_v2_float, n_preset_frames_freq,3);
        bind_method(&sn_render_proc, m_render_proc, GDEXTENSION_VARIANT_TYPE_NIL,0, t_v2, n_frames,1);
        NameBuf sn_trans; make_name(&sn_trans,"transition");
        bind_method(&sn_trans, m_transition, GDEXTENSION_VARIANT_TYPE_NIL,0, t_mood_root_bpm_fade, n_mood_root_bpm_fade,4);
        registered=1;
    }

    if(!registered_amb){
        GDExtensionClassCreationInfo6 info2; memset(&info2,0,sizeof(info2));
        info2.is_exposed=1;
        info2.create_instance_func=create_amb_instance;
        info2.free_instance_func=free_amb_instance;
        api.classdb_register_extension_class6(lib_ptr, &sn_amb_class, &sn_parent, &info2);

        GDExtensionVariantType t_v2[1]={GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY};
        const NameBuf *n_frames[1]={&sn_frames};
        GDExtensionVariantType t_biome_tod_weather[3]={GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT};
        const NameBuf *n_biome_tod_weather[3]={&sn_biome,&sn_tod,&sn_weather};
        GDExtensionVariantType t_weather_int[2]={GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_FLOAT};
        const NameBuf *n_weather_int[2]={&sn_weather,&sn_intensity};
        GDExtensionVariantType t_gain_fade[2]={GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_FLOAT};
        const NameBuf *n_gain_fade[2]={&sn_gain,&sn_bpm};

        bind_method_amb(&sn_amb_render, m_amb_render, GDEXTENSION_VARIANT_TYPE_NIL,0, t_v2, n_frames,1);
        bind_method_amb(&sn_amb_set_biome, m_amb_set_biome, GDEXTENSION_VARIANT_TYPE_NIL,0, t_biome_tod_weather, n_biome_tod_weather,3);
        bind_method_amb(&sn_amb_set_weather, m_amb_set_weather, GDEXTENSION_VARIANT_TYPE_NIL,0, t_weather_int, n_weather_int,2);
        bind_method_amb(&sn_amb_set_gain, m_amb_set_gain, GDEXTENSION_VARIANT_TYPE_NIL,0, t_gain_fade, n_gain_fade,2);
        registered_amb=1;
    }
}
static void unregister_class(void){
    if(registered){
        api.classdb_unregister_extension_class(lib_ptr,&sn_class);
        registered=0;
    }
    if(registered_amb){
        api.classdb_unregister_extension_class(lib_ptr,&sn_amb_class);
        registered_amb=0;
    }
}
static void init_level(void *ud, GDExtensionInitializationLevel lvl){
    (void)ud; if(lvl==GDEXTENSION_INITIALIZATION_SCENE) register_class();
}
static void deinit_level(void *ud, GDExtensionInitializationLevel lvl){
    (void)ud; if(lvl==GDEXTENSION_INITIALIZATION_SCENE) unregister_class();
}
static int load_sym(void *dest, size_t sz, GDExtensionInterfaceGetProcAddress get_proc, const char *sym){
    GDExtensionInterfaceFunctionPtr fn=get_proc(sym);
    if(!fn || sz!=sizeof(fn)) return 0;
    memcpy(dest,&fn,sz); return 1;
}
static int load_api(GDExtensionInterfaceGetProcAddress get_proc){
#define LOAD(f,s) if(!load_sym(&api.f,sizeof(api.f),get_proc,s)) return 0;
    LOAD(get_godot_version2,"get_godot_version2");
    LOAD(mem_alloc,"mem_alloc");
    LOAD(mem_free,"mem_free");
    LOAD(print_error,"print_error");
    LOAD(classdb_register_extension_class6,"classdb_register_extension_class6");
    LOAD(classdb_unregister_extension_class,"classdb_unregister_extension_class");
    LOAD(classdb_register_extension_class_method,"classdb_register_extension_class_method");
    LOAD(classdb_construct_object3,"classdb_construct_object3");
    LOAD(object_set_instance,"object_set_instance");
    LOAD(string_name_new_with_utf8_chars,"string_name_new_with_utf8_chars");
    LOAD(string_new_with_utf8_chars,"string_new_with_utf8_chars");
    LOAD(variant_new_nil,"variant_new_nil");
    LOAD(variant_destroy,"variant_destroy");
    LOAD(variant_get_type,"variant_get_type");
    LOAD(variant_call,"variant_call");
    LOAD(get_variant_from_type_constructor,"get_variant_from_type_constructor");
    LOAD(get_variant_to_type_constructor,"get_variant_to_type_constructor");
    GDExtensionInterfaceFunctionPtr tmp;
    tmp=get_proc("variant_get_ptr_internal_getter");
    if(!tmp) return 0;
    GDExtensionInterfaceVariantGetPtrInternalGetter get_ptr = (GDExtensionInterfaceVariantGetPtrInternalGetter)tmp;
    tmp=get_proc("packed_float32_array_operator_index"); if(!tmp) return 0; memcpy(&api.packed_f32_op,&tmp,sizeof(tmp));
    tmp=get_proc("packed_vector2_array_operator_index"); if(!tmp) return 0; memcpy(&api.packed_v2_op,&tmp,sizeof(tmp));
    tmp=get_proc("packed_int32_array_operator_index"); if(!tmp) return 0; memcpy(&api.packed_i32_op,&tmp,sizeof(tmp));
#undef LOAD
    api.from_bool=api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL);
    api.from_int=api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
    api.from_float=api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
    api.to_int=api.get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
    api.to_float=api.get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
    api.to_bool=api.get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL);
    api.packed_f32_ptr=get_ptr(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
    api.packed_v2_ptr=get_ptr(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
    api.packed_i32_ptr=get_ptr(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    if(!api.from_bool||!api.from_int||!api.to_int||!api.to_float||!api.packed_f32_ptr||!api.packed_v2_ptr) return 0;
    return 1;
}
AG_EXPORT GDExtensionBool audio_gen_library_init(GDExtensionInterfaceGetProcAddress p_get_proc, GDExtensionClassLibraryPtr p_lib, GDExtensionInitialization *r_init){
    if(!p_get_proc||!r_init||!load_api(p_get_proc)) return 0;
    lib_ptr=p_lib;
    r_init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;
    r_init->userdata=0;
    r_init->initialize=init_level;
    r_init->deinitialize=deinit_level;
    return 1;
}
