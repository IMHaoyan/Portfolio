using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class rotateX : MonoBehaviour
{
    public Transform target;
    public float speed = 10.0f;
    private Vector3 point;

    void Start () {
        point = target.position;
        //transform.LookAt(point);
    }

    void Update () {
        transform.RotateAround(point, Vector3.forward, speed * Time.deltaTime);
    }
}
