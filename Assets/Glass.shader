Shader "ACG/GlassShader"
{
    Properties
    {
        [Header(Vidrio)]
        _Tint ("Color del vidrio", Color) = (0.85,0.95,1,1)
        _Refraction ("Refraccion", Range(0,0.3)) = 0.08
        _Reflection ("Reflejo", Range(0,1)) = 0.8
        _Clarity ("Nitidez del reflejo", Range(0,1)) = 1
        _Dispersion ("Arcoiris en los bordes", Range(0,1)) = 0.3

        [Header(Vidrio Roto)]
        _Shatter ("Romper", Range(0,1)) = 0.4
        _ShardSize ("Cantidad de pedazos", Range(1,20)) = 4
        _CenterY ("Altura del centro", Range(-3,3)) = 0
        _Float ("Flotar", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Cull Off
        GrabPass { "_GlassGrab" }

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

            sampler2D _GlassGrab;
            float4 _Tint;
            float _Refraction, _Reflection, _Clarity, _Dispersion, _Shatter, _ShardSize, _CenterY, _Float;

            struct v2g { float3 opos : TEXCOORD0; float3 normal : TEXCOORD1; };
            struct g2f
            {
                float4 pos : SV_POSITION; float4 grab : TEXCOORD0; float3 wpos : TEXCOORD1;
                float3 normal : TEXCOORD2; float3 opos : TEXCOORD3; float3 cell : TEXCOORD4;
            };

            float hash(float3 p) { p = frac(p * 0.1031); p += dot(p, p.zyx + 31.32); return frac((p.x + p.y) * p.z); }
            float3 hash3(float3 p) { return float3(hash(p), hash(p + 17.1), hash(p + 31.7)); }

            float3 Voronoi(float3 p, out float edge)
            {
                float3 i = floor(p), f = frac(p), cell = i;
                float d1 = 8, d2 = 8;
                for (int x = -1; x <= 1; x++)
                for (int y = -1; y <= 1; y++)
                for (int z = -1; z <= 1; z++)
                {
                    float3 g = float3(x, y, z);
                    float d = length(g + hash3(i + g) - f);
                    if (d < d1) { d2 = d1; d1 = d; cell = i + g; }
                    else d2 = min(d2, d);
                }
                edge = d2 - d1;
                return cell;
            }

            float3 ShardCell(float3 p, out float edge, out float3 pivot)
            {
                float3 big = Voronoi(p * _ShardSize, edge);
                float3 r = hash3(big);
                pivot = (big + r) / _ShardSize;
                if (r.x > 0.7) return big;

                float3 axis = normalize(r - 0.5 + 1e-4);
                float3 q = p * _ShardSize * 2.5;
                q -= axis * dot(q, axis) * 0.7;
                float e2;
                float3 small = Voronoi(q + big * 7.31, e2);
                edge = min(edge, e2 * 0.6);
                return big * 1000 + small;
            }

            float3 Rotate(float3 v, float3 axis, float a)
            {
                float s, c; sincos(a, s, c);
                return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1 - c);
            }

            v2g vert(appdata_base v)
            {
                v2g o;
                o.opos = v.vertex.xyz;
                o.normal = v.normal;
                return o;
            }

            [maxvertexcount(9)]
            void geom(triangle v2g IN[3], inout TriangleStream<g2f> stream)
            {
                float e; float3 p0, p1, p2;
                float3 cells[3] = { ShardCell(IN[0].opos, e, p0), ShardCell(IN[1].opos, e, p1), ShardCell(IN[2].opos, e, p2) };
                float3 pivots[3] = { p0, p1, p2 };

                for (int k = 0; k < 3; k++)
                {
                    if ((k > 0 && all(cells[k] == cells[0])) || (k == 2 && all(cells[2] == cells[1]))) continue;
                    float3 cell = cells[k], r = hash3(cell), pivot = pivots[k];

                    float3 dir = normalize(pivot - float3(0, _CenterY, 0) + 1e-4);
                    float3 axis = normalize(r - 0.5 + 1e-4);
                    float angle = _Shatter * ((r.z - 0.5) * 4 + sin(_Time.y + r.x * 6.28) * _Float);
                    float3 move = dir * _Shatter * (0.5 + r.y) + float3(0, sin(_Time.y * 1.5 + r.x * 6.28) * 0.1 * _Float * _Shatter, 0);

                    for (int j = 0; j < 3; j++)
                    {
                        float3 p = Rotate(IN[j].opos - pivot, axis, angle) + pivot + move;
                        g2f o;
                        o.pos = UnityObjectToClipPos(p);
                        o.grab = ComputeGrabScreenPos(o.pos);
                        o.wpos = mul(unity_ObjectToWorld, float4(p, 1)).xyz;
                        o.normal = UnityObjectToWorldNormal(Rotate(IN[j].normal, axis, angle));
                        o.opos = IN[j].opos;
                        o.cell = cell;
                        stream.Append(o);
                    }
                    stream.RestartStrip();
                }
            }

            fixed4 frag(g2f i, fixed facing : VFACE) : SV_Target
            {
                float edge; float3 pv;
                clip(0.5 - distance(ShardCell(i.opos, edge, pv), i.cell));

                float3 N = normalize(i.normal) * (facing > 0 ? 1 : -1);
                float3 V = normalize(_WorldSpaceCameraPos - i.wpos);

                float2 bend = mul((float3x3)UNITY_MATRIX_V, N).xy * _Refraction * i.grab.w;
                float spread = 1 + _Dispersion * 0.3;
                float3 behind;
                behind.r = tex2Dproj(_GlassGrab, i.grab + float4(bend * spread, 0, 0)).r;
                behind.g = tex2Dproj(_GlassGrab, i.grab + float4(bend, 0, 0)).g;
                behind.b = tex2Dproj(_GlassGrab, i.grab + float4(bend / spread, 0, 0)).b;

                float3 env = DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflect(-V, N), (1 - _Clarity) * 6), unity_SpecCube0_HDR);
                float fresnel = 0.05 + 0.95 * pow(1 - saturate(dot(N, V)), 4);
                float3 col = lerp(behind * _Tint.rgb, env, saturate(fresnel * _Reflection * 1.5));

                float3 H = normalize(_WorldSpaceLightPos0.xyz + V);
                col += pow(saturate(dot(N, H)), 600) * _LightColor0.rgb * 4;
                col = lerp(col, float3(1, 1, 1), (1 - smoothstep(0.01, 0.035, edge)) * saturate(_Shatter * 4) * 0.8);
                return fixed4(col, 1);
            }
            ENDCG
        }
    }
}
