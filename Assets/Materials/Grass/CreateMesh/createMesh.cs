using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class createMesh : MonoBehaviour
{
    public int MeshSize = 10;
    public int MeshLength = 10;
    int[] vertIndexs;       //网格三角形索引
                            //Vector3[] positions;    //位置
                            // Vector2[] uvs;          //uv坐标
    Mesh mesh;
    MeshFilter filetr;
    MeshRenderer render;
    public Material Mat;     //泡沫材质
    private void Awake()
    {
        filetr = gameObject.GetComponent<MeshFilter>();
        render = gameObject.GetComponent<MeshRenderer>();
        mesh = new Mesh();
        render.material = Mat;
        CreateMesh();
        filetr.mesh = mesh;
    }
    private void Update()
    {

        //mesh = new Mesh();
        //filetr.mesh = mesh;
        //CreateMesh();
    }

    void CreateMesh()
    {
        //fftSize = (int)Mathf.Pow(2, FFTPow);
        vertIndexs = new int[(MeshSize - 1) * (MeshSize - 1) * 6];
        Vector3[] positions = new Vector3[MeshSize * MeshSize];
        Vector2[] uvs = new Vector2[MeshSize * MeshSize];
        Vector4[] tangents = new Vector4[MeshSize * MeshSize];
        Vector3[] normals = new Vector3[MeshSize * MeshSize];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);
        Vector3 normal = new Vector4(0f, 1f, 0f);
        //MeshSize实际上是顶点数量
        int inx = 0;
        for (int i = 0; i < MeshSize; i++)
        {
            for (int j = 0; j < MeshSize; j++)
            {
                int index = i * MeshSize + j;
                positions[index] = new Vector3((j - MeshSize / 2.0f) * MeshLength / MeshSize, 0, (i - MeshSize / 2.0f) * MeshLength / MeshSize);
                uvs[index] = new Vector2(j / (MeshSize - 1.0f), i / (MeshSize - 1.0f));
                tangents[index] = tangent;
                normals[index] = normal;
                if (i != MeshSize - 1 && j != MeshSize - 1)
                {
                    vertIndexs[inx++] = index;
                    vertIndexs[inx++] = index + MeshSize;
                    vertIndexs[inx++] = index + MeshSize + 1;

                    vertIndexs[inx++] = index;
                    vertIndexs[inx++] = index + MeshSize + 1;
                    vertIndexs[inx++] = index + 1;
                }
            }
        }
        mesh.vertices = positions;
        mesh.SetIndices(vertIndexs, MeshTopology.Triangles, 0);
        mesh.uv = uvs;
        mesh.tangents = tangents;

        mesh.normals = normals;
    }

}
