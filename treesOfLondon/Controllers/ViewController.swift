//
//  ViewController.swift
//  treesOfLondon
//
//  Created by Andras Pal on 14/04/2020.
//  Copyright © 2020 Andras Pal. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation

class ViewController: UIViewController, MKMapViewDelegate {
    
    @IBOutlet private var mapView: MKMapView!
    @IBAction private func infoButtonPressed(_ sender: UIButton) {
        let infoPanel = InfoPanelController()
        infoPanel.modalPresentationStyle = .fullScreen
        present(infoPanel, animated: true, completion: nil)
    }
    @IBAction private func locationButtonPressed(_ sender: UIButton) {
        updateLocationService(didShowLocationWarning)
        setLocationOnMap()
        didShowLocationWarning = true
    }
    @IBOutlet private weak var loadingView: LoadingLabelView!
    @IBOutlet private weak var locationButton: UIButton!
    @IBOutlet private weak var infoButton: UIButton!
    
    private var trees: [Trees] = []
    
    private let defaultLocation = CLLocation(latitude: kLocations.defaultLocation.latitude, longitude: kLocations.defaultLocation.longitude)
    private let zoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: kUI.ZoomRange.large)
    fileprivate let locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()
        return manager
    }()
    private var didShowLocationWarning: Bool = false
    
    override func viewDidLoad() {
        
        super.viewDidLoad()

        mapView.register(
            TreeMarkerView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(
            ClusterView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        
        loadInitialData { (data, error) in
            if data != nil {
                self.mapView.addAnnotations(self.trees)
                self.loadingView.fadeOut()
            }
        }
        
        loadingView.fadeIn()
        loadingView.buttonShadow()
        locationButton.buttonShadow()
        infoButton.buttonShadow()
        setUpMapView()
    }
    
    private func setUpMapView() {
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.centerToLocation(location: defaultLocation, regionRadius: kUI.ZoomRange.maxDistance)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.setLocationOnMap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.setBoundary()
            }
        }
    }
    
    private func setBoundary() {
        let region = MKCoordinateRegion(
            center: defaultLocation.coordinate,
            latitudinalMeters: kUI.ZoomRange.maxDistance,
            longitudinalMeters: kUI.ZoomRange.maxDistance)
        mapView.setCameraBoundary(
            MKMapView.CameraBoundary(coordinateRegion: region),
            animated: true)
        mapView.setCameraZoomRange(zoomRange, animated: true)
    }
    
    /// For checking the current location of the user
    private func currentLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = true
        } else {
            // Fallback on earlier versions
        }
        locationManager.startUpdatingLocation()
    }
    
    /// For updating the location on the map.
    /// If the user in London then the app can use that location, otherwise it's gonna use a default location
    private func setLocationOnMap() {
        
        let isUserInLondon: Bool = checkIfInLondon(latitude: Double((locationManager.location?.coordinate.latitude ?? 0.1)),
                                                   longitude: Double((locationManager.location?.coordinate.longitude ?? 0.1)))
        
        if checkLocationService() == LocationServiceStatus.authInUseAlways && isUserInLondon {
            print("Location: \(String(describing: locationManager.location?.coordinate))")
            print(("User is in London: \(isUserInLondon)"))
            currentLocation()
        } else {
            mapView.centerToLocation(location: defaultLocation, regionRadius: kUI.ZoomRange.small)
        }
    }
    
    /// For checking if a coordinate is in the useful area or not - we need to know if the user is in London or not
    /// - Parameters:
    ///   - latitude: the latitude
    ///   - longitude: the longitude
    /// - Returns: a bool
    private func checkIfInLondon(latitude: Double, longitude: Double) -> Bool {
        if (latitude > 51.35 && latitude < 51.7) && (longitude > -0.55 && longitude < 0.2) {
            return true
        } else {
            return false
        }
    }
    
    private func loadInitialData(completion: @escaping (_ data: [Trees]?, _ error: Error?) -> ()) {
        
        var receivedError: Error?
        
        DispatchQueue.global(qos: .userInteractive).async {
            guard
                let fileName = Bundle.main.url(forResource: "londonTrees_Final", withExtension: "geojson"),
                let treeData = try? Data(contentsOf: fileName)
            else {
                return
            }
            do {
                let features = try MKGeoJSONDecoder()
                    .decode(treeData)
                    .compactMap { $0 as? MKGeoJSONFeature }
                let allTrees = features.compactMap(Trees.init)
                self.trees.append(contentsOf: allTrees)
                
            } catch {
                receivedError = error
            }
            DispatchQueue.main.async {
                completion(self.trees, receivedError)
            }
        }
    }
}

//MARK: - Extensions
extension ViewController: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last! as CLLocation
        let currentLocation = location.coordinate
        let coordinateRegion = MKCoordinateRegion(center: currentLocation, latitudinalMeters: kUI.ZoomRange.small, longitudinalMeters: kUI.ZoomRange.small)
        mapView.setRegion(coordinateRegion, animated: true)
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error.localizedDescription)
    }
    
    /// For checking the authorizationStatus of the CLLocationManager
    /// - Returns: A LocationServiceStatus enum case
    func checkLocationService() -> LocationServiceStatus {
        /// Check if the app can use Location Services
        if CLLocationManager.locationServicesEnabled() {
            
            switch CLLocationManager.authorizationStatus() {
            
            case .notDetermined:
                return .notDetermined
            case .restricted, .denied:
                return .restrictedDenied
            case .authorizedWhenInUse, .authorizedAlways:
                return .authInUseAlways
            @unknown default:
                return .unknownDefault
            }
        } else {
            return .unknownDefault
        }
    }
    
    /// For handling the different cases of the CLLocationManager's authorization statuses.
    /// Can request access to the location services or continue running if already has access.
    func updateLocationService(_ didShowLocationWarning: Bool? = false) {
        /// Check if user has authorized the app to use Location Services
        if CLLocationManager.locationServicesEnabled() {
            
            switch checkLocationService() {
            
            case .notDetermined:
                // Request using the location service
                self.locationManager.delegate = self
                locationManager.requestWhenInUseAuthorization()
                break
                
            case .restrictedDenied:
                // Creating an alert to use the location service
                let alert = UIAlertController(title: String.getString(.locAccess), message: String.getString(.locAccessWarning), preferredStyle: UIAlertController.Style.alert)
                // Alert to Open Settings
                alert.addAction(UIAlertAction(title: String.getString(.settings), style: UIAlertAction.Style.default, handler: { action in
                    guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    if UIApplication.shared.canOpenURL(settingsUrl) {
                        UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                            print("Settings opened: \(success)")
                        })
                    }
                }))
                alert.addAction(UIAlertAction(title: String.getString(.ok), style: UIAlertAction.Style.default, handler: nil))
                (didShowLocationWarning ?? false) ? nil : self.present(alert, animated: true, completion: nil)
                break
                
            case .authInUseAlways:
                // Enable features that require location services here.
                print("Has access to location")
                break
                
            case .unknownDefault:
                fatalError()
            }
        }
    }
}
