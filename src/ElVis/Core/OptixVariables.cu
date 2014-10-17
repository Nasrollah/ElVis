///////////////////////////////////////////////////////////////////////////////
//
// The MIT License
//
// Copyright (c) 2006 Scientific Computing and Imaging Institute,
// University of Utah (USA)
//
// License for the specific language governing rights and limitations under
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//
///////////////////////////////////////////////////////////////////////////////

#ifndef ELVIS_OPTIX_VARIABLES_CU
#define ELVIS_OPTIX_VARIABLES_CU


#include <optix_cuda.h>
#include <optix_math.h>
#include <optixu/optixu_matrix.h>
#include <optixu/optixu_aabb.h>
#include <ElVis/Core/CutSurfacePayloads.cu>
#include <ElVis/Core/FaceInfo.h>

// Communication with OptiX is accomplished via global, named variables.
// Each variable must be defined and visible to the OptiX programs at global
// scope, then set in the host code at runtime.

// These buffers are all sized to the display size, each entry corresponding
// to a single pixel.

// The final color to display, in (r,g,b,a).
rtBuffer<uchar4, 2> color_buffer;

// This buffer holds intermediate color calculations.  When all calculations
// have completed, the final image is generated by truncating the values here
// and storing them in color_buffer.
rtBuffer<ElVisFloat3, 2> raw_color_buffer;

// For debugging purposes, we want to be able to know what the scalar value 
// is on a cut surface for a given pixel.  This buffer stores all sample
// values for fast retrieval.
rtBuffer<ElVisFloat, 2> SampleBuffer;

// The normal of the the surface at the given pixel.
rtBuffer<ElVisFloat3, 2> normal_buffer;

// The intersection point of the surface at the given pixel.
rtBuffer<ElVisFloat3, 2> intersection_buffer;

// The depth value at each pixel.
rtBuffer<float, 2> depth_buffer;

// This group should contain all surfaces that are meant to be rendered 
// directly.  Examples include cut-surface and element faces.  Element faces
// that are not meant to be rendered directly should not go into this group.
rtDeclareVariable(rtObject, SurfaceGeometryGroup, , );

// This group contains all elemental faces.  Ray tracing into this group 
// will return the closest element face.  2D elements do not belong in this 
// group.  Currently used by isosurfaces and volume rendering to go from 
// element to element, but they do use the PointLocation group to find the element
// between faces.
rtDeclareVariable(rtObject, PlanarFaceGroup, ,);
rtDeclareVariable(rtObject, CurvedFaceGroup, ,);

// Currently commented out in the volume rendering.  May be my trial code.
// Most likely, only one of ElementTraversalGroup and faceGroup need to remain.
// Currently, face intersection sets the face id and only applies if the face is 
// turned on.
rtDeclareVariable(rtObject, faceGroup, , );

//The dimensionality of the model, i.e. 2D or 3D
rtDeclareVariable(int, ModelDimension, , );

rtDeclareVariable(ElVisFloat3, normal, attribute normal_vec, );

rtDeclareVariable(int, FieldId, , );

rtDeclareVariable(optix::Ray, ray, rtCurrentRay, );
rtDeclareVariable(uint2, launch_index, rtLaunchIndex, );
rtDeclareVariable(int, EnableTrace, , );
rtDeclareVariable(int2, TracePixel, , );

rtDeclareVariable(ElementFinderPayload, intersectionPointPayload, rtPayload, );

rtDeclareVariable(CutSurfaceScalarValuePayload, payload, rtPayload, );

rtDeclareVariable(ElVisFloat3, VolumeMinExtent, , );
rtDeclareVariable(ElVisFloat3, VolumeMaxExtent, , );


rtBuffer<int, 2> ElementIdBuffer;
rtBuffer<int, 2> ElementTypeBuffer;

rtDeclareVariable(float, closest_t, rtIntersectionDistance, );





// For depth buffer calculations for interop with OpenGL.
rtDeclareVariable(float, near, , );
rtDeclareVariable(float, far, , );
rtDeclareVariable(int, DepthBits, , );

// All vertices defined by the model.
rtBuffer<ElVisFloat4> VertexBuffer;

/////////////////////////////////////////////////////////////////////////////
// Faces
//
// Faces have a global index and a type-specific index.  ElVis currently 
// distinguishes between planar and curved faces.  Each planar face will have a 
// global face index and a different planar face index.  Similarly for curved 
// faces.
/////////////////////////////////////////////////////////////////////////////

// Generic information about each face that is valid regardless of the type of face.
// Indexing is by global face index.
rtBuffer<ElVis::FaceInfo, 1> FaceInfoBuffer;

// Buffer indicating which faces are enabled for viewing and which are not.
// Indexins is by global face index.
rtBuffer<unsigned char, 1> FaceEnabled;

// Information about each planar face. 
// Indexing is by local planar face index.
rtBuffer<ElVis::PlanarFaceInfo, 1> PlanarFaceInfoBuffer;

rtBuffer<uint, 1> PlanarFaceToGlobalIdxMap;
rtBuffer<uint, 1> CurvedFaceToGlobalIdxMap;
rtBuffer<uint, 1> GlobalFaceToPlanarFaceIdxMap;
rtBuffer<uint, 1> GlobalFaceToCurvedFaceIdxMap;

rtBuffer<ElVisFloat4> PlanarFaceNormalBuffer;


struct PlanarFaceTag;
struct CurvedFaceTag;
struct GlobalFaceTag;

struct PlanarFaceIdx
{
  __device__ PlanarFaceIdx() {};

  __device__ PlanarFaceIdx(int v) : Value(v) {}

  int Value;
};

struct CurvedFaceIdx
{
  __device__ CurvedFaceIdx() {};

  __device__ CurvedFaceIdx(int v) : Value(v) {}

  int Value;
};

struct GlobalFaceIdx
{
  __device__ GlobalFaceIdx() {};

  __device__ GlobalFaceIdx(const PlanarFaceIdx& rhs) :
    Value(PlanarFaceToGlobalIdxMap[rhs.Value])
  {
  }

  __device__ GlobalFaceIdx(const CurvedFaceIdx& rhs) :
    Value(CurvedFaceToGlobalIdxMap[rhs.Value])
  {
  }

  __device__ GlobalFaceIdx(int v) : Value(v) {}

  int Value;
};

__device__ PlanarFaceIdx ConvertToPlanarFaceIdx(const GlobalFaceIdx& globalIdx)
{
  return PlanarFaceIdx(GlobalFaceToPlanarFaceIdxMap[globalIdx.Value]);
}

__device__ CurvedFaceIdx ConvertToCurvedFaceIdx(const GlobalFaceIdx& globalIdx)
{
  return CurvedFaceIdx(GlobalFaceToCurvedFaceIdxMap[globalIdx.Value]);
}

__device__ GlobalFaceIdx ConvertToGlobalFaceIdx(const PlanarFaceIdx& planarIdx)
{
    return GlobalFaceIdx(PlanarFaceToGlobalIdxMap[planarIdx.Value]);
}

__device__ GlobalFaceIdx ConvertToGlobalFaceIdx(const CurvedFaceIdx& curvedIdx)
{
    return GlobalFaceIdx(CurvedFaceToGlobalIdxMap[curvedIdx.Value]);
}

__device__ unsigned char GetFaceEnabled(GlobalFaceIdx idx)
{
    return FaceEnabled[idx.Value];
}

__device__ const ElVis::FaceInfo& GetFaceInfo(GlobalFaceIdx globalFaceIdx)
{
    return FaceInfoBuffer[globalFaceIdx.Value];
}



rtDeclareVariable(GlobalFaceIdx, intersectedFaceGlobalIdx, attribute IntersectedFaceId, );
rtDeclareVariable(ElVisFloat2, faceIntersectionReferencePoint, attribute FaceIntersectionReferencePoint, );
rtDeclareVariable(bool, faceIntersectionReferencePointIsValid, attribute FaceIntersectionReferencePointIsValid, );

rtDeclareVariable(ElVisFloat3, HeadlightColor, ,);


#endif

