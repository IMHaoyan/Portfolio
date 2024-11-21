using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class InteractGrass : MonoBehaviour
{
    public Material material;
    public float radius = 2f;
    public float strength = 1f;

    void Update()
    {
        material.SetVector("_PositionMoving", GetComponent<Transform>().position);
        
        material.SetFloat("_Radius", radius);
        
        material.SetFloat("_Strength", strength);
    }
}
