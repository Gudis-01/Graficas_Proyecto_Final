using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Networking;

public static class DescargarCielo
{
    const string Url = "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/venice_sunset_2k.hdr";
    const string TexPath = "Assets/Cielo/venice_sunset_2k.hdr";
    const string MatPath = "Assets/Cielo/Cielo.mat";

    [MenuItem("Tools/ACG/Poner cielo Venice Sunset")]
    static void PonerCielo()
    {
        Directory.CreateDirectory("Assets/Cielo");

        if (!File.Exists(TexPath))
        {
            using (var req = UnityWebRequest.Get(Url))
            {
                var op = req.SendWebRequest();
                while (!op.isDone)
                    EditorUtility.DisplayProgressBar("Cielo", "Descargando Venice Sunset...", req.downloadProgress);
                EditorUtility.ClearProgressBar();
                if (req.result != UnityWebRequest.Result.Success) { Debug.LogError("[Cielo] " + req.error); return; }
                File.WriteAllBytes(TexPath, req.downloadHandler.data);
            }
            AssetDatabase.ImportAsset(TexPath);
        }

        var tex = AssetDatabase.LoadAssetAtPath<Texture>(TexPath);
        var mat = AssetDatabase.LoadAssetAtPath<Material>(MatPath);
        if (mat == null)
        {
            mat = new Material(Shader.Find("Skybox/Panoramic"));
            AssetDatabase.CreateAsset(mat, MatPath);
        }
        mat.SetTexture("_MainTex", tex);
        mat.SetFloat("_Exposure", 1.2f);

        RenderSettings.skybox = mat;
        DynamicGI.UpdateEnvironment();
        UnityEditor.SceneManagement.EditorSceneManager.MarkSceneDirty(UnityEngine.SceneManagement.SceneManager.GetActiveScene());
        AssetDatabase.SaveAssets();
        Debug.Log("[Cielo] Listo: skybox Venice Sunset aplicado.");
    }
}
