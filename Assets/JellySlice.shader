Shader "ACG/JellySliceShader"
{
    Properties
    {
        [Header(Modelo)]
        _MainTex ("Textura", 2D) = "white" {}
        _Color ("Color base", Color) = (1,1,1,1)

        [Header(Placas)]
        _SliceSize ("Tamano de las placas", Range(0.02,1)) = 0.13
        _Variety ("Variedad de tamanos", Range(0,1)) = 0.7
        _Depth ("Grosor de las placas", Range(0,1.5)) = 1
        _CenterY ("Altura del centro", Range(-3,3)) = 0.6

        [Header(Movimiento)]
        _Relief ("Relieve (hundir y sacar)", Range(0,1)) = 0.35
        _Breath ("Respiracion", Range(0,1)) = 0.3
        _Speed ("Velocidad", Range(0,3)) = 0.5
        _Gloss ("Brillo", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        Cull Off

        Pass
        {
            Tags { "LightMode"="ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            #pragma target 4.0
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            sampler2D _MainTex; float4 _MainTex_ST;
            float4 _Color;
            float _SliceSize, _Variety, _Depth, _CenterY, _Relief, _Breath, _Speed, _Gloss;

            struct v2g { float3 opos : TEXCOORD0; float3 onormal : TEXCOORD1; float2 uv : TEXCOORD2; };
            struct g2f
            {
                float4 pos : SV_POSITION; float3 normal : TEXCOORD0; float2 uv : TEXCOORD1;
                float3 opos : TEXCOORD2;
                float4 id : TEXCOORD3;
            };

            float hash(float3 p) { p = frac(p * 0.1031); p += dot(p, p.zyx + 31.32); return frac((p.x + p.y) * p.z); }
            float3 hash3(float3 p) { return float3(hash(p), hash(p + 17.1), hash(p + 31.7)); }

            float3 CellSize() { return _SliceSize * float3(1.6, 1.0, 1.2); }

            void PlateBox(float3 base, float sub, out float3 bmin, out float3 bsize)
            {
                float3 cell = CellSize(), r = hash3(base);
                bmin = base * cell + float3(0, _CenterY, 0); bsize = cell;
                if (sub < 0.5) return;
                float3 axis = r.y < 0.4 ? float3(1, 0, 0) : (r.y < 0.75 ? float3(0, 1, 0) : float3(0, 0, 1));
                float cut = lerp(0.35, 0.65, r.z);
                bmin += sub < 1.5 ? float3(0, 0, 0) : axis * cell * cut;
                bsize = lerp(bsize, bsize * (sub < 1.5 ? cut : 1 - cut), axis);
            }

            float4 Plate(float3 p)
            {
                float3 cell = CellSize(), q = p - float3(0, _CenterY, 0);
                float3 base = floor(q / cell), r = hash3(base);
                if (r.x >= _Variety) return float4(base, 0);
                float3 axis = r.y < 0.4 ? float3(1, 0, 0) : (r.y < 0.75 ? float3(0, 1, 0) : float3(0, 0, 1));
                return float4(base, dot(q / cell - base, axis) < lerp(0.35, 0.65, r.z) ? 1 : 2);
            }

            float3 PlateOffset(float4 id)
            {
                float3 bmin, bsize; PlateBox(id.xyz, id.w, bmin, bsize);
                float r = hash(id.xyz + id.w * 7.7);
                float3 dir = normalize(bmin + bsize * 0.5 - float3(0, _CenterY, 0) + 1e-4);
                float breath = sin(_Time.y * _Speed * 2 + r * 6.28);
                return dir * _SliceSize * ((r - 0.4) * _Relief + breath * _Breath * 0.25);
            }

            v2g vert(appdata_base v)
            {
                v2g o;
                o.opos = v.vertex.xyz;
                o.onormal = v.normal;
                o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                return o;
            }

            void EmitLayer(float3 p[3], v2g IN[3], float back, inout TriangleStream<g2f> stream)
            {
                float3 pts[4] = { p[0], p[1], p[2], (p[0] + p[1] + p[2]) / 3 };
                float3 bases[4];
                for (int k = 0; k < 4; k++)
                {
                    bases[k] = floor((pts[k] - float3(0, _CenterY, 0)) / CellSize());
                    bool repeated = false;
                    for (int m = 0; m < k; m++) repeated = repeated || all(bases[m] == bases[k]);
                    if (repeated) continue;

                    bool split = hash3(bases[k]).x < _Variety;
                    for (int sub = split ? 1 : 0; sub <= (split ? 2 : 0); sub++)
                    {
                        float4 id = float4(bases[k], sub);
                        float3 off = PlateOffset(id);
                        for (int j = 0; j < 3; j++)
                        {
                            g2f o;
                            o.pos = UnityObjectToClipPos(p[j] + off);
                            o.normal = UnityObjectToWorldNormal(IN[j].onormal);
                            o.uv = IN[j].uv;
                            o.opos = p[j];
                            o.id = id + float4(0, 0, 0, back * 10);
                            stream.Append(o);
                        }
                        stream.RestartStrip();
                    }
                }
            }

            [maxvertexcount(48)]
            void geom(triangle v2g IN[3], inout TriangleStream<g2f> stream)
            {
                float t = _SliceSize * _Depth;
                float3 skin[3]  = { IN[0].opos, IN[1].opos, IN[2].opos };
                float3 inner[3] = { IN[0].opos - IN[0].onormal * t, IN[1].opos - IN[1].onormal * t, IN[2].opos - IN[2].onormal * t };
                EmitLayer(skin, IN, 0, stream);
                EmitLayer(inner, IN, 1, stream);
            }

            fixed4 frag(g2f i, fixed facing : VFACE) : SV_Target
            {
                bool back = i.id.w > 5;
                float4 id = float4(i.id.xyz, i.id.w - (back ? 10 : 0));
                clip(0.5 - distance(Plate(i.opos), id));

                float3 bmin, bsize; PlateBox(id.xyz, id.w, bmin, bsize);
                float3 off = PlateOffset(id);
                float3 wpos = mul(unity_ObjectToWorld, float4(i.opos + off, 1)).xyz;
                float3 V = normalize(_WorldSpaceCameraPos - wpos);
                float3 L = _WorldSpaceLightPos0.xyz;
                bool front = facing > 0 && !back;
                float3 albedo = tex2D(_MainTex, i.uv).rgb * _Color.rgb;

                float3 camObj = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz - off;
                float3 s = (i.opos - bmin) / bsize, c = (camObj - bmin) / bsize, dir = s - c;
                float3 t = (step(dir, 0) - c) / (dir + 1e-6);
                float3 side = (t.x >= t.y && t.x >= t.z) ? float3(-sign(dir.x), 0, 0)
                            : (t.y >= t.z) ? float3(0, -sign(dir.y), 0) : float3(0, 0, -sign(dir.z));

                float3 N = front ? normalize(i.normal) : UnityObjectToWorldNormal(side);
                float3 base = front ? albedo : albedo * 0.35;

                float diff = saturate(dot(N, L));
                float spec = pow(saturate(dot(N, normalize(L + V))), lerp(8, 96, _Gloss)) * _Gloss * 0.5 * front;
                float3 col = base * (diff * _LightColor0.rgb + ShadeSH9(float4(N, 1)) * (front ? 1 : 0.5)) + spec * _LightColor0.rgb;
                return fixed4(col, 1);
            }
            ENDCG
        }
    }
}
