# Third-party components

## SFace face recognition model
- File: `Sources/Eymra/Resources/FaceEmbedding.mlpackage` (Core ML, float16)
- Source: OpenCV Zoo, `models/face_recognition_sface/face_recognition_sface_2021dec.onnx`
  (https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface)
- Paper: Zhong et al., "SFace: Sigmoid-Constrained Hypersphere Loss for Robust Face Recognition", IEEE TIP 2021.
- Licence: Apache License 2.0 (`SFace-LICENSE.txt`).
- Conversion: ONNX → PyTorch (onnx2torch 1.5.15) → Core ML (coremltools 8.3, iOS 18 target, float16). Input `face`: 112×112 RGB image,
  pixel values 0–255, aligned to the ArcFace 5-point template. Output `embedding`: 128 floats, L2-normalised in the app.
- Checked: Core ML output matches ONNX Runtime (cosine 1.000 on 8 test inputs). On 1,000 LFW test pairs with 5-point alignment:
  98.8 % accuracy at cosine 0.363, no false matches; the app uses 0.40.
