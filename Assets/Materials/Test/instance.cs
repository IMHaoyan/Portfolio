using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class instance : MonoBehaviour
{
    // Start is called before the first frame update
    public GameObject cube;  //定义一个cube来存放要随机生成的预制体
    void Start()
    {
        for (var i = 0; i < 50; i++)
        {
            float x = 0;
            float z = -50 + i*2;
            Instantiate(cube, new Vector3(x, 0.5f, z), Quaternion.identity);//随机生成物体（预制体，生成的位置，方向）。
        }
    }
    void Update()
    {
    }
}
