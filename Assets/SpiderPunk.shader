// ACG / SpiderPunkShader - Estilo Hobie Brown (Across the Spider-Verse)
// Pasadas: 1) color toon con puntos y rayado  2) linea de tinta  3) recorte de revista
Shader "ACG/SpiderPunkShader"
{
    Properties
    {
        [Header(Color)]
        _MainTex ("Textura", 2D) = "white" {}
        _Color ("Color base", Color) = (1,1,1,1)
        _ShadowColor ("Color de sombra", Color) = (0.22,0.12,0.34,1)
        _InkColor ("Color de tinta", Color) = (0.05,0.01,0.08,1)

        [Header(Sombreado Comic)]
        _ShadowAmount ("Cantidad de sombra", Range(0,1)) = 0.3
        _DotSize ("Tamano de los puntos", Range(0,1)) = 0.6
        _Hatching ("Rayado en sombras", Range(0,1)) = 0.7

        [Header(Acento Punk)]
        _AccentColor ("Color de acento", Color) = (1,0.1,0.55,1)
        _AccentAmount ("Intensidad de acento", Range(0,1)) = 0.7

        [Header(Linea y Recorte)]
        _OutlineWidth ("Grosor de linea", Range(0,12)) = 3
        _CutoutColor ("Color del recorte", Color) = (0.98,0.93,0.78,1)
        _CutoutSize ("Tamano del recorte", Range(0,40)) = 14
        [ToggleUI] _UseSmoothNormals ("Modelo con esquinas duras", Float) = 0

        [Header(Animacion)]
        _StopMotion ("Efecto stop-motion", Range(0,1)) = 0.6
        _ShadowFPS ("FPS sombras", Range(1,24)) = 12
        _LineFPS ("FPS linea", Range(1,24)) = 8
        _CutoutFPS ("FPS recorte", Range(1,24)) = 6
    }

    CGINCLUDE
    #include "UnityCG.cginc"
    sampler2D _MainTex; float4 _MainTex_ST;
    float4 _Color, _ShadowColor, _InkColor, _AccentColor, _CutoutColor;
    float _ShadowAmount, _DotSize, _Hatching, _AccentAmount, _OutlineWidth, _CutoutSize;
    float _UseSmoothNormals, _StopMotion, _ShadowFPS, _LineFPS, _CutoutFPS;

    // Numero pseudoaleatorio 0..1
    float hash(float3 p) { p = frac(p * 0.1031); p += dot(p, p.zyx + 31.32); return frac((p.x + p.y) * p.z); }
    float2 rot(float2 v, float deg) { float s, c; sincos(radians(deg), s, c); return float2(c*v.x - s*v.y, s*v.x + c*v.y); }

    // Reloj a pasos: cada capa avanza a su propio FPS
    float Tick(float fps) { return floor(_Time.y * fps) * step(0.001, _StopMotion); }
    float2 Jitter(float t, float px) { return (float2(hash(float3(t,1,7)), hash(float3(t,5,3))) - 0.5) * px * _StopMotion; }

    // ---- Cascarones inflados (linea y recorte) ----
    struct appdataHull { float4 vertex : POSITION; float3 normal : NORMAL; float4 tangent : TANGENT; float4 smoothN : TEXCOORD3; };

    // Normal normal o suavizada (del baker) para que no se abran las esquinas
    float3 GetNormal(appdataHull v)
    {
        float4 s = v.smoothN;
        if (_UseSmoothNormals < 0.5 || dot(s.xyz, s.xyz) < 1e-6) return v.normal;
        float3 b = cross(v.normal, v.tangent.xyz) * v.tangent.w;
        return s.w > 0.5 ? v.tangent.xyz * s.x + b * s.y + v.normal * s.z : s.xyz;
    }

    // Empuja el vertice hacia afuera N pixeles (mismo grosor a cualquier distancia)
    float4 HullVert(appdataHull v, float widthPx, float2 extraPx)
    {
        float3 viewN = mul((float3x3)UNITY_MATRIX_V, UnityObjectToWorldNormal(GetNormal(v)));
        float2 dir = normalize(mul((float2x2)UNITY_MATRIX_P, viewN.xy) * _ScreenParams.xy + 1e-5);
        float4 pos = UnityObjectToClipPos(v.vertex);
        pos.xy += (dir * widthPx + extraPx) * 2.0 / _ScreenParams.xy * pos.w;
        return pos;
    }
    ENDCG

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        // ===== PASADA 1: color comic =====
        Pass
        {
            Tags { "LightMode"="ForwardBase" }
            Stencil { Ref 64 Pass Replace }   // marca los pixeles del personaje

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            struct v2f
            {
                float4 pos : SV_POSITION; float2 uv : TEXCOORD0; float3 normal : TEXCOORD1;
                float3 worldPos : TEXCOORD2; float4 screen : TEXCOORD3; float4 center : TEXCOORD4;
                SHADOW_COORDS(5)
            };

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.screen = ComputeScreenPos(o.pos);
                o.center = ComputeScreenPos(UnityObjectToClipPos(float3(0,0,0)));  // pivote del objeto
                TRANSFER_SHADOW(o);
                return o;
            }

            // Puntos de halftone: crecen segun "amount"
            float Dots(float2 uv, float amount, float angle)
            {
                float d = length(frac(rot(uv, angle)) - 0.5);
                float r = sqrt(saturate(amount)) * 0.75, aa = fwidth(d) + 1e-4;
                return step(0.001, amount) * (1 - smoothstep(r - aa, r + aa, d));
            }

            // Lineas paralelas de grosor "width"
            float Lines(float2 uv, float width, float angle)
            {
                float f = abs(frac(rot(uv, angle).x) - 0.5) * 2, aa = fwidth(f) + 1e-4;
                return step(0.001, width) * (1 - smoothstep(width - aa, width + aa, f));
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 N = normalize(i.normal);
                float3 V = normalize(_WorldSpaceCameraPos - i.worldPos);
                float NdotL = dot(N, _WorldSpaceLightPos0.xyz);
                float light = saturate(NdotL) * SHADOW_ATTENUATION(i);

                // Zonas: luz -> puntos -> sombra -> sombra profunda
                float edge = lerp(0.05, 0.6, _ShadowAmount);
                float shadow = step(light, edge);
                float dark = saturate((edge + 0.4 - light) / 0.4);
                float deep = saturate(1 - light / edge) * shadow;

                // Colores planos (posterizado) + toon de 2 bandas
                float3 albedo = floor(tex2D(_MainTex, i.uv).rgb * _Color.rgb * 5 + 0.5) / 5;
                float3 col = albedo * lerp(saturate(_LightColor0.rgb + 0.3), _ShadowColor.rgb, shadow);

                // Coordenadas de pantalla ancladas al objeto (los puntos no "nadan")
                float2 uv = (i.screen.xy / i.screen.w - i.center.xy / i.center.w) * i.center.w / 5;
                uv.x *= _ScreenParams.x / _ScreenParams.y;
                uv = uv * lerp(120, 15, _DotSize) + Jitter(Tick(_ShadowFPS), 0.5);

                col = lerp(col, _AccentColor.rgb, Dots(uv + 0.3, dark * 0.6 + shadow * 0.25, 15) * _AccentAmount); // puntos de acento desfasados
                col = lerp(col, _InkColor.rgb, Dots(uv, dark, 45) * (1 - shadow));                              // puntos de tinta
                col = lerp(col, _InkColor.rgb, Lines(uv * 2, deep * _Hatching * 0.6, 135));                     // rayado en sombra

                float rim = step(0.72, 1 - saturate(dot(N, V))) * saturate(NdotL + 0.3);                         // borde de acento
                return fixed4(lerp(col, _AccentColor.rgb, rim * _AccentAmount), 1);
            }
            ENDCG
        }

        // ===== PASADA 2: linea de tinta =====
        Pass
        {
            Cull Front
            Stencil { Ref 64 Pass Replace }

            CGPROGRAM
            #pragma vertex vertLine
            #pragma fragment fragLine

            float4 vertLine(appdataHull v) : SV_POSITION
            {
                float t = Tick(_LineFPS);
                float w = _OutlineWidth * (0.6 + 0.8 * hash(v.vertex.xyz * 13.7 + t)); // grosor tipo pincel que hierve
                return HullVert(v, w, Jitter(t, 3));
            }
            fixed4 fragLine() : SV_Target { return _InkColor; }
            ENDCG
        }

        // ===== PASADA 3: recorte de revista (solo fuera del personaje) =====
        Pass
        {
            Stencil { Ref 64 Comp NotEqual }

            CGPROGRAM
            #pragma vertex vertCut
            #pragma fragment fragCut

            float4 vertCut(appdataHull v) : SV_POSITION
            {
                float t = Tick(_CutoutFPS);
                float facet = hash(floor(GetNormal(v) * 3) + t);   // cortes de tijera por zonas
                float on = step(0.01, _CutoutSize);
                return HullVert(v, _CutoutSize * (0.65 + 0.7 * facet), (float2(5, -4) + Jitter(t, 5)) * on);
            }
            fixed4 fragCut(float4 pos : SV_POSITION) : SV_Target
            {
                float d = length(frac(rot(pos.xy, 30) / 9) - 0.5);   // puntos impresos de revista
                return fixed4(lerp(_CutoutColor.rgb, _AccentColor.rgb, step(d, 0.23) * 0.35 * _AccentAmount), 1);
            }
            ENDCG
        }

        UsePass "Legacy Shaders/VertexLit/SHADOWCASTER"
    }
    FallBack "Diffuse"
}