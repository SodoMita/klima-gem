#include "ag_biome.h"
#include <string.h>
#include <math.h>

void ag_biome_params_default(AgBiomeParams *p, AgBiomeType type) {
    memset(p,0,sizeof(*p));
    p->type=type;
    p->seed=1;
    p->time_of_day=0.5f;
    p->humidity=0.5f;
    p->weather_type=AG_WEATHER_CLEAR;
    p->weather=0.0f;
    switch(type){
        case AG_BIOME_FOREST: p->wind=0.32f; p->water=0.22f; p->birds=0.72f; p->insects=0.52f; p->humidity=0.62f; break;
        case AG_BIOME_CAVE: p->wind=0.12f; p->water=0.62f; p->birds=0.0f; p->insects=0.12f; p->humidity=0.92f; break;
        case AG_BIOME_DESERT: p->wind=0.62f; p->water=0.0f; p->birds=0.12f; p->insects=0.32f; p->humidity=0.12f; break;
        case AG_BIOME_OCEAN: p->wind=0.52f; p->water=1.0f; p->birds=0.32f; p->insects=0.0f; p->humidity=0.82f; break;
        case AG_BIOME_CITY: p->wind=0.22f; p->water=0.12f; p->birds=0.22f; p->insects=0.0f; p->humidity=0.42f; break;
        case AG_BIOME_MOUNTAIN: p->wind=0.72f; p->water=0.22f; p->birds=0.32f; p->insects=0.12f; p->humidity=0.32f; break;
        case AG_BIOME_JUNGLE: p->wind=0.22f; p->water=0.52f; p->birds=0.92f; p->insects=0.92f; p->humidity=0.92f; break;
        case AG_BIOME_SWAMP: p->wind=0.16f; p->water=0.72f; p->birds=0.32f; p->insects=0.82f; p->humidity=0.92f; break;
        case AG_BIOME_TUNDRA: p->wind=0.82f; p->water=0.12f; p->birds=0.12f; p->insects=0.0f; p->humidity=0.22f; break;
        case AG_BIOME_GRASSLAND: p->wind=0.42f; p->water=0.12f; p->birds=0.62f; p->insects=0.62f; p->humidity=0.42f; break;
        case AG_BIOME_RIVER: p->wind=0.22f; p->water=0.92f; p->birds=0.52f; p->insects=0.42f; p->humidity=0.62f; break;
        case AG_BIOME_BEACH: p->wind=0.42f; p->water=0.82f; p->birds=0.42f; p->insects=0.22f; p->humidity=0.72f; break;
        case AG_BIOME_NEXUS: p->wind=0.32f; p->water=0.32f; p->birds=0.22f; p->insects=0.22f; p->humidity=0.52f; break;
        case AG_BIOME_RIFT: p->wind=0.52f; p->water=0.12f; p->birds=0.0f; p->insects=0.0f; p->humidity=0.32f; break;
        case AG_BIOME_LAB: p->wind=0.06f; p->water=0.0f; p->birds=0.0f; p->insects=0.0f; p->humidity=0.22f; break;
        default: break;
    }
}

void ag_biome_init(AgBiome *biome, const AgBiomeParams *params, double sr) {
    memset(biome,0,sizeof(*biome));
    biome->sr=sr>0?sr:AG_SR_DEFAULT;
    biome->params=*params;
    biome->gain=1.0f;
    ag_rng_seed(&biome->rng, params->seed?params->seed:1);

    ag_wind_sys_init(&biome->wind, sr);
    ag_wind_sys_set(&biome->wind, params->wind*0.52f, params->wind*0.62f, params->wind*0.42f);

    ag_ocean_init(&biome->ocean, sr);
    ag_ocean_set(&biome->ocean, params->water, 0.45f);

    ag_river_init(&biome->river, sr);
    ag_stream_init(&biome->stream, sr);
    ag_waterfall_init(&biome->waterfall, sr);
    ag_drip_init(&biome->drip, sr);

    ag_fire_init(&biome->fire, sr);

    for(int i=0;i<4;i++) ag_bird_init(&biome->birds[i], sr, (i+ (int)params->seed)%5);
    for(int i=0;i<2;i++) ag_cricket_init(&biome->crickets[i], sr);
    for(int i=0;i<2;i++) ag_cicada_init(&biome->cicadas[i], sr);
    for(int i=0;i<2;i++) ag_frog_init(&biome->frogs[i], sr);
    for(int i=0;i<1;i++) ag_owl_init(&biome->owls[i], sr);

    ag_swarm_init(&biome->swarm, sr);
    ag_weather_mixer_init(&biome->weather, sr);
    ag_weather_mixer_set(&biome->weather, params->weather_type, params->weather);

    ag_drone_init(&biome->drone, sr, 55.0f);
    ag_granular_init(&biome->granular, sr, 110.0f);
}

void ag_biome_set_params(AgBiome *biome, const AgBiomeParams *params) {
    biome->params=*params;
    ag_wind_sys_set(&biome->wind, params->wind*0.52f, params->wind*0.62f, params->wind*0.42f);
    ag_ocean_set(&biome->ocean, params->water, 0.45f);
    ag_weather_mixer_set(&biome->weather, params->weather_type, params->weather);
}

float ag_biome_next(AgBiome *biome) {
    float l,r; ag_biome_next_stereo(biome,&l,&r); return (l+r)*0.5f;
}
void ag_biome_next_stereo(AgBiome *biome, float *out_l, float *out_r) {
    float mix_l=0, mix_r=0;

    /* Wind HQ */
    float wind_l, wind_r;
    ag_wind_sys_next_stereo(&biome->wind, &wind_l, &wind_r);
    wind_l *= biome->params.wind;
    wind_r *= biome->params.wind;
    mix_l+=wind_l*0.32f;
    mix_r+=wind_r*0.32f;

    /* Water HQ */
    if(biome->params.water > 0.01f){
        float water_l=0, water_r=0;
        switch(biome->params.type){
            case AG_BIOME_OCEAN:
            case AG_BIOME_BEACH:
                ag_ocean_next_stereo(&biome->ocean, &water_l, &water_r);
                break;
            case AG_BIOME_RIVER:
                ag_river_next_stereo(&biome->river, &water_l, &water_r);
                break;
            case AG_BIOME_CAVE:
                ag_drip_auto(&biome->drip, biome->params.water);
                ag_drip_next_stereo(&biome->drip, &water_l, &water_r);
                /* add subtle river for cave */
                {
                    float rl, rr;
                    ag_river_next_stereo(&biome->river, &rl, &rr);
                    water_l += rl*0.15f;
                    water_r += rr*0.15f;
                }
                break;
            case AG_BIOME_MOUNTAIN:
            case AG_BIOME_TUNDRA:
                ag_waterfall_next_stereo(&biome->waterfall, &water_l, &water_r);
                break;
            default:
                ag_stream_next_stereo(&biome->stream, &water_l, &water_r);
                break;
        }
        /* humidity affects low-pass for water */
        float hum = biome->params.humidity;
        float water_gain = biome->params.water * (0.8f + hum*0.3f);
        mix_l+=water_l*water_gain;
        mix_r+=water_r*water_gain;
    }

    /* Birds HQ - stereo */
    if(biome->params.birds > 0.01f){
        float day_factor = sinf(biome->params.time_of_day * (float)AG_PI);
        day_factor = ag_clamp_f(day_factor, 0,1);
        float bird_gain = biome->params.birds * (0.4f + day_factor*0.8f);
        float bl=0, br=0;
        for(int i=0;i<4;i++){
            ag_bird_auto(&biome->birds[i], biome->params.birds * (0.5f + day_factor*0.6f) * (0.8f + i*0.1f));
            float l,r;
            ag_bird_next_stereo(&biome->birds[i], &l, &r);
            /* pan birds around */
            float pan = sinf((float)i*1.3f + biome->params.time_of_day*2.0f) * 0.6f;
            float pl, pr;
            ag_buffer_pan_stereo(l+r, pan, &pl, &pr);
            bl+=pl*0.22f; br+=pr*0.22f;
        }
        mix_l+=bl*bird_gain;
        mix_r+=br*bird_gain;
    }

    /* Insects HQ */
    if(biome->params.insects > 0.01f){
        float insect_l=0,insect_r=0;
        float day_factor = sinf(biome->params.time_of_day * (float)AG_PI);
        float night_factor = 1.0f - day_factor;
        day_factor = ag_clamp_f(day_factor,0,1);
        night_factor = ag_clamp_f(night_factor,0,1);

        if(day_factor>0.15f){
            for(int i=0;i<2;i++){
                float l,r;
                ag_cicada_next_stereo(&biome->cicadas[i], &l, &r);
                insect_l+=l*0.16f*day_factor;
                insect_r+=r*0.16f*day_factor;
            }
            float sl, sr;
            ag_swarm_next_stereo(&biome->swarm, &sl, &sr);
            insect_l+=sl*0.35f*day_factor;
            insect_r+=sr*0.35f*day_factor;
        }
        if(night_factor>0.15f){
            for(int i=0;i<2;i++){
                float l,r;
                ag_cricket_next_stereo(&biome->crickets[i], &l, &r);
                /* night crickets panned wide */
                float pan = (i==0?-0.7f:0.7f) + sinf(biome->params.time_of_day*0.5f+i)*0.2f;
                float pl,pr;
                ag_buffer_pan_stereo(l+r, pan, &pl, &pr);
                insect_l+=pl*0.18f*night_factor;
                insect_r+=pr*0.18f*night_factor;
            }
        }
        if(biome->params.type==AG_BIOME_SWAMP || biome->params.type==AG_BIOME_JUNGLE){
            for(int i=0;i<2;i++){
                float l,r;
                ag_frog_next_stereo(&biome->frogs[i], &l, &r);
                insect_l+=l*0.22f;
                insect_r+=r*0.22f;
            }
        }
        if(night_factor>0.45f){
            for(int i=0;i<1;i++){
                float l,r;
                ag_owl_next_stereo(&biome->owls[i], &l, &r);
                insect_l+=l*0.22f;
                insect_r+=r*0.22f;
            }
        }

        mix_l+=insect_l*biome->params.insects;
        mix_r+=insect_r*biome->params.insects;
    }

    /* Fire HQ */
    if(biome->params.fire > 0.01f){
        float fl, fr;
        ag_fire_next_stereo(&biome->fire, &fl, &fr);
        mix_l+=fl*biome->params.fire*0.52f;
        mix_r+=fr*biome->params.fire*0.52f;
    }

    /* Weather HQ */
    if(biome->params.weather > 0.01f){
        float wl,wr;
        ag_weather_mixer_next_stereo(&biome->weather, &wl, &wr);
        mix_l+=wl*biome->params.weather*0.9f;
        mix_r+=wr*biome->params.weather*0.9f;
    }

    /* Drone for cave/nexus/rift with filtering */
    if(biome->params.type==AG_BIOME_CAVE || biome->params.type==AG_BIOME_NEXUS || biome->params.type==AG_BIOME_RIFT){
        float d=ag_drone_next(&biome->drone) * 0.32f;
        /* add subtle stereo chorus */
        float chorus = sinf((float)biome->sr * 0.0001f) * 0.05f;
        mix_l+=d*(0.5f+chorus);
        mix_r+=d*(0.5f-chorus);
    }
    if(biome->params.type==AG_BIOME_NEXUS){
        float g=ag_granular_next(&biome->granular) * 0.22f;
        mix_l+=g*0.6f;
        mix_r+=g*0.4f;
    }

    /* High-quality soft clip with tanh + slight saturation */
    mix_l = tanhf(mix_l*0.92f)*1.08f;
    mix_r = tanhf(mix_r*0.92f)*1.08f;
    /* gentle high-shelf for air */
    mix_l = ag_clamp_f(mix_l, -1.2f, 1.2f);
    mix_r = ag_clamp_f(mix_r, -1.2f, 1.2f);

    *out_l = mix_l * biome->gain;
    *out_r = mix_r * biome->gain;
}
void ag_biome_render(AgBiome *biome, float *stereo_interleaved, int frames) {
    for(int i=0;i<frames;i++){
        float l,r; ag_biome_next_stereo(biome,&l,&r);
        stereo_interleaved[i*2]=l;
        stereo_interleaved[i*2+1]=r;
    }
}

AgBiomeType ag_biome_from_string(const char *str) {
    if(!str) return AG_BIOME_FOREST;
    if(strcmp(str,"forest")==0) return AG_BIOME_FOREST;
    if(strcmp(str,"cave")==0) return AG_BIOME_CAVE;
    if(strcmp(str,"desert")==0) return AG_BIOME_DESERT;
    if(strcmp(str,"ocean")==0) return AG_BIOME_OCEAN;
    if(strcmp(str,"city")==0) return AG_BIOME_CITY;
    if(strcmp(str,"mountain")==0) return AG_BIOME_MOUNTAIN;
    if(strcmp(str,"jungle")==0) return AG_BIOME_JUNGLE;
    if(strcmp(str,"swamp")==0) return AG_BIOME_SWAMP;
    if(strcmp(str,"tundra")==0) return AG_BIOME_TUNDRA;
    if(strcmp(str,"grassland")==0) return AG_BIOME_GRASSLAND;
    if(strcmp(str,"river")==0) return AG_BIOME_RIVER;
    if(strcmp(str,"beach")==0) return AG_BIOME_BEACH;
    if(strcmp(str,"nexus")==0) return AG_BIOME_NEXUS;
    if(strcmp(str,"rift")==0) return AG_BIOME_RIFT;
    if(strcmp(str,"lab")==0) return AG_BIOME_LAB;
    if(strcmp(str,"classroom")==0) return AG_BIOME_CITY;
    if(strcmp(str,"grove")==0) return AG_BIOME_FOREST;
    if(strcmp(str,"shore")==0) return AG_BIOME_BEACH;
    if(strcmp(str,"sanctum")==0) return AG_BIOME_CAVE;
    if(strcmp(str,"core")==0) return AG_BIOME_CAVE;
    if(strcmp(str,"festival")==0) return AG_BIOME_CITY;
    if(strcmp(str,"alley")==0) return AG_BIOME_CITY;
    if(strcmp(str,"lighthouse")==0) return AG_BIOME_OCEAN;
    return AG_BIOME_FOREST;
}
const char* ag_biome_to_string(AgBiomeType type) {
    switch(type){
        case AG_BIOME_FOREST: return "forest";
        case AG_BIOME_CAVE: return "cave";
        case AG_BIOME_DESERT: return "desert";
        case AG_BIOME_OCEAN: return "ocean";
        case AG_BIOME_CITY: return "city";
        case AG_BIOME_MOUNTAIN: return "mountain";
        case AG_BIOME_JUNGLE: return "jungle";
        case AG_BIOME_SWAMP: return "swamp";
        case AG_BIOME_TUNDRA: return "tundra";
        case AG_BIOME_GRASSLAND: return "grassland";
        case AG_BIOME_RIVER: return "river";
        case AG_BIOME_BEACH: return "beach";
        case AG_BIOME_NEXUS: return "nexus";
        case AG_BIOME_RIFT: return "rift";
        case AG_BIOME_LAB: return "lab";
        default: return "forest";
    }
}
