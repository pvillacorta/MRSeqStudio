import * as css from "./index.css";
import * as utils from "./utils_private";
import { openScreen, initTabs } from "./style"


import "@kitware/vtk.js/Rendering/Profiles/All"
import vtkGenericRenderWindow from "@kitware/vtk.js/Rendering/Misc/GenericRenderWindow"
import "@kitware/vtk.js/IO/Core/DataAccessHelper/HttpDataAccessHelper"
import DataAccessHelper from "@kitware/vtk.js/IO/Core/DataAccessHelper"
import { niftiReadImage } from "@itk-wasm/image-io"
import vtkITKHelper from "@kitware/vtk.js/Common/DataModel/ITKHelper"
import vtkImageSlice from "@kitware/vtk.js/Rendering/Core/ImageSlice"
import vtkInteractorStyleImage from "@kitware/vtk.js/Interaction/Style/InteractorStyleImage"
import vtkImageResliceMapper from "@kitware/vtk.js/Rendering/Core/ImageResliceMapper"
import vtkPlane from "@kitware/vtk.js/Common/DataModel/Plane"
import { SlabTypes } from "@kitware/vtk.js/Rendering/Core/ImageResliceMapper/Constants"
import vtkImplicitPlaneRepresentation from '@kitware/vtk.js/Widgets/Representations/ImplicitPlaneRepresentation';

let niftiFile
let niftiUrl

let imageData
let renderer3d
let renderWindow3d

let colorWindow = 0;
let colorLevel  = 0;

let planeNormal = [0, 0, -1]
let planeCenter = [0, 0, 0]

// i, j, k planes
const iPlane = vtkPlane.newInstance()
const jPlane = vtkPlane.newInstance()
const kPlane = vtkPlane.newInstance()
iPlane.setNormal([1, 0, 0])
jPlane.setNormal([0, 1, 0])
kPlane.setNormal([0, 0, 1])
const iMapper = vtkImageResliceMapper.newInstance()
const jMapper = vtkImageResliceMapper.newInstance()
const kMapper = vtkImageResliceMapper.newInstance()
const iActor3d = vtkImageSlice.newInstance()
const jActor3d = vtkImageSlice.newInstance()
const kActor3d = vtkImageSlice.newInstance()

// Selected plane
const slicePlane = vtkPlane.newInstance()
slicePlane.setNormal(planeNormal)
const resliceMapper = vtkImageResliceMapper.newInstance()
const resliceActor = vtkImageSlice.newInstance()

// Outline (vtkImplicitPlaneRepresentation)
const representation = vtkImplicitPlaneRepresentation.newInstance();
const state = vtkImplicitPlaneRepresentation.generateState();

async function setNormalPlane(gx, gy, gz, deltaf, gamma){
  planeNormal = [gx, gy, gz]

  let norm = Math.sqrt(gx * gx + gy * gy + gz * gz);
  if (norm === 0) {
      console.error("El vector planeNormal es nulo.");
      return null;
  }

  let r = deltaf / (gamma * norm);

  let rv =  [   
      r * (gx / norm) * 1000, // mm
      r * (gy / norm) * 1000, // mm
      r * (gz / norm) * 1000  // mm
  ]

  planeCenter = imageData.getCenter().map(
      (c, i) => c + rv[i]
  )

  let spacing = imageData.getSpacing(); // Devuelve [sx, sy, sz] en mm por voxel
  console.log("Espaciado de voxel:", spacing);

  addSlicePlane()
  renderWindow3d.render()
}
window.setNormalPlane = setNormalPlane

async function displayVolume(filename){
  niftiFile = `${filename}/T1.nii.gz`
  niftiUrl  = `../public/nifti_phantoms/${niftiFile}`

  document.getElementById("VTKjs").style.display = "none";
  document.getElementById("loading-vtk").style.display = "block";

  try{
    await loadNifti();
    // Remove previous actors
    renderer3d.removeActor(resliceActor);
    representation.getActors().forEach(actor => {
      renderer3d.removeActor(actor);
    });
    // load 3 orthogonal slices
    addReslicerToRenderer();
    // Render
    renderWindow3d.render();
  }catch(error){
    console.log(error);
  }finally{
    document.getElementById("loading-vtk").style.display = "none"; 
    document.getElementById("VTKjs").style.display = "block";
  }
}
window.displayVolume = displayVolume


async function setup() {
  const genericRenderer3d = vtkGenericRenderWindow.newInstance({
    background: [ 0.188,
                  0.200,
                  0.212 ] 
  })
  genericRenderer3d.setContainer(document.querySelector("#VTKjs"))
  genericRenderer3d.resize()
  renderer3d = genericRenderer3d.getRenderer()
  renderWindow3d = genericRenderer3d.getRenderWindow()
}

async function loadNifti() {
  const dataAccessHelper = DataAccessHelper.get("http")
  // @ts-ignore - bad typings
  const niftiArrayBuffer = await dataAccessHelper.fetchBinary(niftiUrl)
  const fileName = niftiFile.split("/")[niftiFile.split("/").length - 1]
  const { image: itkImage, webWorker } = await niftiReadImage({
    data: new Uint8Array(niftiArrayBuffer),
    // tienes que darle el nombre del archivo, no sé muy bien por qué
    path: fileName
  })
  webWorker.terminate()
  // convertir formato itk a vtk
  imageData = vtkITKHelper.convertItkToVtkImage(itkImage)
}

function addReslicerToRenderer() {
  planeCenter = imageData.getCenter()

  // i, j, k planes
  iPlane.setOrigin(planeCenter)
  jPlane.setOrigin(planeCenter)
  kPlane.setOrigin(planeCenter)

  iMapper.setSlicePlane(iPlane)
  jMapper.setSlicePlane(jPlane)
  kMapper.setSlicePlane(kPlane)

  iMapper.setInputData(imageData)
  jMapper.setInputData(imageData)
  kMapper.setInputData(imageData)

  iActor3d.setMapper(iMapper)
  jActor3d.setMapper(jMapper)
  kActor3d.setMapper(kMapper)

  updateColorLevelandWindow();

  iActor3d.getProperty().setColorLevel(colorLevel);
  jActor3d.getProperty().setColorLevel(colorLevel);
  kActor3d.getProperty().setColorLevel(colorLevel);

  iActor3d.getProperty().setColorWindow(colorWindow);
  jActor3d.getProperty().setColorWindow(colorWindow);
  kActor3d.getProperty().setColorWindow(colorWindow);

  renderer3d.addActor(iActor3d)
  renderer3d.addActor(jActor3d)
  renderer3d.addActor(kActor3d)

  renderer3d.resetCamera()
  renderer3d.resetCameraClippingRange()
}

function addSlicePlane(){
  // Selected plane
  slicePlane.setNormal(planeNormal);

  slicePlane.setOrigin(planeCenter)
  resliceMapper.setSlicePlane(slicePlane)
  resliceMapper.setInputData(imageData)
  resliceActor.setMapper(resliceMapper)

  resliceActor.getProperty().setColorLevel(colorLevel);
  resliceActor.getProperty().setColorWindow(colorWindow);

  renderer3d.addActor(resliceActor)

  const bounds = imageData.getBounds()

  state.placeWidget(bounds);

  state.setOrigin(planeCenter)
  state.setNormal(planeNormal)

  representation.setInputData(state);
  representation.getActors().forEach(renderer3d.addActor);
  
  renderer3d.resetCamera()
  renderer3d.resetCameraClippingRange()
}

function updateColorLevelandWindow() {
  const scalars = imageData.getPointData().getScalars().getData();
  let min =  Infinity;
  let max = -Infinity;
  for (let i = 0; i < scalars.length; i++) {
    const v = scalars[i];
    if (v < min) min = v;
    if (v > max) max = v;
  }
  colorWindow = max - min;
  colorLevel  =  min + colorWindow / 2;
}

async function main() {
  initTabs()
  setup()
  document.getElementById("btn-screenEditor").onclick = function() {openScreen('screenEditor')}
  document.getElementById("btn-screenSeq").onclick = function() {openScreen('screenSeq')}
  document.getElementById("btn-screen3DViewer").onclick = function() {openScreen('screen3DViewer')}
  document.getElementById("btn-screenSimulator").onclick = function() {openScreen('screenSimulator')}
}

main()

