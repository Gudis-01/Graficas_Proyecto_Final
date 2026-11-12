// ACG / StrangeCubesShader - El modelo se transforma en cubos (Doctor Strange)
// Geometry shader: cada triangulo se convierte en un cubo que nace dentro de su triangulo
// (no se enciman) y sale sobre su normal. Separacion 0 = modelo original.
Shader "ACG/StrangeCubesShader"
{
    Properties
    {
        [Header(Modelo)]
        _MainTex ("Textura", 2D) = "white" {}
        _Color ("Color base", Color) = (1,1,1,1)

        [Header(Cubos)]
        _Split ("Separacion", Range(0,1)) = 0.12
        _CubeScale ("Tamano de los cubos", Range(0.2,1)) = 0.99
        _Breath ("Respiracion", Range(0,1)) = 0.4

        [Header(Interior y Aristas)]
        _InnerColor ("Color del interior", Color) = (0.03,0.01,0.08,1)
        [HDR] _EdgeColor ("Color de las aristas", Color) = (2.5,1.2,0.3,1)
        _EdgeWidth ("Grosor de las aristas", Range(0,0.3)) = 0.08
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
            float4 _Color, _InnerColor, _EdgeColor;
            float _Split, _CubeScale, _Breath, _EdgeWidth;

            struct v2g { float3 wpos : TEXCOORD0; float3 normal : TEXCOORD1; float2 uv : TEXCOORD2; float3 opos : TEXCOORD3; };
            struct g2f
            {
                float4 pos : SV_POSITION; float3 wpos : TEXCOORD0; float3 normal : TEXCOORD1;
                float2 uv : TEXCOORD2; float3 local : TEXCOORD3; float3 center : TEXCOORD4; float f : TEXCOORD5;
            };

            // Cubo unitario en una tira de 14 vertices (z = 1 es la cara de afuera)
            static const float3 CUBE[14] = {
                float3(0,1,1), float3(1,1,1), float3(0,0,1), float3(1,0,1), float3(1,0,0), float3(1,1,1), float3(1,1,0),
                float3(0,1,1), float3(0,1,0), float3(0,0,1), float3(0,0,0), float3(1,0,0), float3(0,1,0), float3(1,1,0) };

            float hash(float3 p) { p = frac(p * 0.1031); p += dot(p, p.zyx + 31.32); return frac((p.x + p.y) * p.z); }

            v2g vert(appdata_base v)
            {
                v2g o;
                o.wpos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                o.opos = v.vertex.xyz;
                return o;
            }

            [maxvertexcount(14)]
            void geom(triangle v2g IN[3], inout TriangleStream<g2f> stream)
            {
                float3 A = IN[0].wpos, B = IN[1].wpos, C = IN[2].wpos;
                float3 n = normalize(cross(B - A, C - A));
                n *= sign(dot(n, IN[0].normal + IN[1].normal + IN[2].normal));   // hacia afuera

                // Cuadrado inscrito en el triangulo (centro = incentro) -> los cubos no se tocan
                float3 len = float3(distance(B, C), distance(C, A), distance(A, B));
                float per = len.x + len.y + len.z;
                float3 I = (len.x * A + len.y * B + len.z * C) / per;
                float2 uvI = (len.x * IN[0].uv + len.y * IN[1].uv + len.z * IN[2].uv) / per;
                float h = length(cross(B - A, C - A)) / per * 0.7071 * _CubeScale;   // medio lado
                float3 t = normalize(B - A);
                float3 b = cross(n, t) * sign(dot(cross(n, t), C - A));
                float3 sq[4] = { I - (t + b) * h, I + (t - b) * h, I + (t + b) * h, I + (b - t) * h };

                // f: 0 = triangulo original, 1 = cubo completo
                float f = saturate(max(_Split, 1 - _CubeScale) * 4);
                float r = hash((IN[0].opos + IN[1].opos + IN[2].opos) * 12.7);
                float breath = 0.5 + 0.5 * sin(_Time.y * 1.5 + r * 6.28);
                float3 move = n * h * 2 * (_Split * 3 * (0.6 + 0.8 * r) + _Breath * 0.5 * breath * f);   // solo sobre la normal
                float depth = h * 2 * f;

                for (int j = 0; j < 14; j++)
                {
                    float3 q = CUBE[j];
                    int k = q.y > 0.5 ? (q.x > 0.5 ? 2 : 3) : (q.x > 0.5 ? 1 : 0);   // esquina del cuadrado
                    int v = min(k, 2);                                               // vertice del triangulo (C se repite)

                    g2f o;
                    o.wpos = lerp(IN[v].wpos, sq[k], f) + move - n * depth * (1 - q.z);   // triangulo -> cubo
                    o.pos = UnityWorldToClipPos(o.wpos);
                    o.normal = IN[v].normal;
                    o.uv = lerp(IN[v].uv, uvI, f);
                    o.local = q;
                    o.center = I + move - n * depth * 0.5;
                    o.f = f;
                    stream.Append(o);
                }
            }

            fixed4 frag(g2f i) : SV_Target
            {
                // Normal suave del modelo (f = 0) o plana de la cara del cubo (f = 1)
                float3 flatN = normalize(cross(ddy(i.wpos), ddx(i.wpos)));
                flatN *= sign(dot(flatN, i.wpos - i.center) + 1e-5);
                float3 N = normalize(lerp(normalize(i.normal), flatN, i.f));

                // Cara de afuera = piel del modelo, las demas = interior
                float3 base = i.local.z > 0.99 ? tex2D(_MainTex, i.uv).rgb * _Color.rgb : _InnerColor.rgb;
                float3 col = base * (saturate(dot(N, _WorldSpaceLightPos0.xyz)) * _LightColor0.rgb + ShadeSH9(float4(N, 1)));

                // Aristas: donde dos coordenadas del cubo tocan el borde
                float3 e = abs(i.local - 0.5) * 2;
                float second = e.x + e.y + e.z - max(e.x, max(e.y, e.z)) - min(e.x, min(e.y, e.z));
                float edge = smoothstep(1 - _EdgeWidth, 1 - _EdgeWidth * 0.4, second) * i.f;
                return fixed4(lerp(col, _EdgeColor.rgb, edge), 1);
            }
            ENDCG
        }
    }
}