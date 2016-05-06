//
//  DataManager.swift
//  BluePic
//
//  Created by Alex Buck on 4/25/16.
//  Copyright © 2016 MIL. All rights reserved.
//

import UIKit
import BMSCore


enum BlueMixDataManagerError: ErrorType {
    case DocDoesNotExist
}

enum BluemixDataManagerNotification : String {
    case GetAllImagesStarted = "GetAllImagesStarted"
    case ImagesRefreshed = "ImagesRefreshed"
    case ImageUploadBegan = "ImageUploadBegan"
    case ImageUploadSuccess = "ImageUploadSuccess"
    case ImageUploadFailure = "ImageUploadFailure"
}


class BluemixDataManager: NSObject {
    
    static let SharedInstance: BluemixDataManager = {
        
        var manager = BluemixDataManager()
        
        return manager
        
    }()
    
    //Data Variables
    var images = [Image]()
    
    var currentUserImages : [Image] {
        get {
            if(CurrentUser.facebookUserId != nil){
                return images.filter({ $0.usersId! == CurrentUser.facebookUserId!})
            }
            else{
                return []
            }
        }
    }
    
    /// photos that were taken during this app session
    var imagesTakenDuringAppSessionById = [String : UIImage]()
    
    // An array of photos that need to be uploaded to object storage and cloudant sync
    var imageUploadQueue : [Image] = []
    
    
    //End Points
    private let kImagesEndPoint = "images"
    private let kUsersEndPoint = "users"
    
    
    //Plist Keys
    private let kKeysPlistName = "keys"
    private let kIsLocalKey = "isLocal"
    private let kBluemixBaseRequestURLKey_local = "bluemixBaseRequestURL_local"
    private let kBluemixBaseRequestURLKey_remote = "bluemixBaseRequestURL_remote"
    private let kBluemixAppRouteKey = "bluemixAppRoute"
    private let kBluemixAppGUIDKey = "bluemixAppGUID"
    private let kBluemixAppRegionKey = "bluemixAppRegion"
    
    //State Variables
    var hasReceievedInitialImages = false
    
    
    
    func initilizeBluemixAppRoute(){
        
        let appRoute = getBluemixAppRoute()
        let appGuid =  getBluemixAppGUID()
        let bluemixRegion = getBluemixAppRegion()
        
        BMSClient.sharedInstance
            .initializeWithBluemixAppRoute(appRoute,
                                           bluemixAppGUID: appGuid,
                                           bluemixRegion: bluemixRegion)
        
    }
    
    
    private func isLocal() -> Bool {
        return Utils.getBoolValueWithKeyFromPlist(kKeysPlistName, key: kIsLocalKey)
    }
    
    func getBluemixBaseRequestURL() -> String {
        if(isLocal()){
            return Utils.getStringValueWithKeyFromPlist(kKeysPlistName, key: kBluemixBaseRequestURLKey_local)
        }
        else{
            return Utils.getStringValueWithKeyFromPlist(kKeysPlistName, key: kBluemixBaseRequestURLKey_remote)
        }
    }
    
    func getBluemixAppRoute() -> String {
        return Utils.getStringValueWithKeyFromPlist(kKeysPlistName, key: kBluemixAppRouteKey)
    }
    
    func getBluemixAppGUID() -> String {
        return Utils.getStringValueWithKeyFromPlist(kKeysPlistName, key: kBluemixAppGUIDKey)
    }
    
    func getBluemixAppRegion() -> String {
        return Utils.getStringValueWithKeyFromPlist(kKeysPlistName, key: kBluemixAppRegionKey)
    }
    
    func localHostHelloTest(){
        
        let appRoute = "http://localhost:8090"//Utils.getKeyFromPlist("keys", key: "backend_route")
        let appGuid =  ""//Utils.getKeyFromPlist("keys", key: "GUID")
        
        //        let appRoute = "https://greatapp.mybluemix.net"
        //        let appGuid = "2fe35477-5410-4c87-1234-aca59511433b"
        let bluemixRegion = BMSClient.REGION_US_SOUTH
        
        BMSClient.sharedInstance
            .initializeWithBluemixAppRoute(appRoute,
                                           bluemixAppGUID: appGuid,
                                           bluemixRegion: bluemixRegion)
        
        let request = Request(url: "/images", method: HttpMethod.GET)
        //request.headers = ["foo":"bar"]
        //request.queryParameters = ["foo":"bar"]
        
        request.sendWithCompletionHandler { (response, error) -> Void in
            if let error = error {
                print ("Error :: \(error)")
            } else {
                print ("Success :: \(response?.responseText)")
            }
        }
        
        //        let logger = Logger.loggerForName("FirstLogger")
        //
        //        logger.debug("This is a debug message")
        //        logger.error("This is an error message")
        //        logger.info("This is an info message")
        //        logger.warn("This is a warning message")
        
    }

    func getImages(){
        
        NSNotificationCenter.defaultCenter().postNotificationName(BluemixDataManagerNotification.GetAllImagesStarted.rawValue, object: nil)
        
        self.getImages({ images in
            
            if let images = images {
                self.images = images
                self.hasReceievedInitialImages = true
                NSNotificationCenter.defaultCenter().postNotificationName(BluemixDataManagerNotification.ImagesRefreshed.rawValue, object: nil)
            }
 
        })
        
    }
    
    
    
    func getImages(result : (images : [Image]?)-> ()){
        
        let requestURL = getBluemixBaseRequestURL() + "/" + kImagesEndPoint
        let request = Request(url: requestURL, method: HttpMethod.GET)
        
        request.sendWithCompletionHandler { (response, error) -> Void in
            if let error = error {
                result(images: nil)
                print ("Error :: \(error)")
            } else {
                
                let images = self.parseGetImagesResponse(response, userId: nil, usersName: nil)
                result(images: images)
            }
        }
  
    }
    
    func getImagesByUserId(userId : String, usersName : String, result : (images : [Image]?)-> ()){
        
        let requestURL = getBluemixBaseRequestURL() + "/" + kUsersEndPoint + "/" + userId + "/" + kImagesEndPoint
        let request = Request(url: requestURL, method: HttpMethod.GET)
        
        request.sendWithCompletionHandler { (response, error) -> Void in
            if let error = error {
                //result(images: nil)
                print ("Error :: \(error)")
            } else {
                
                let images = self.parseGetImagesResponse(response, userId: userId, usersName: usersName)
                result(images: images)
                
                let response = Utils.convertResponseToDictionary(response)
                print(response)
            }
        }
        
    }
    
    private func parseGetImagesResponse(response : Response?, userId : String?, usersName : String?) -> [Image]{
        var images = [Image]()
        
        if let dict = Utils.convertResponseToDictionary(response),
            let records = dict["records"] as? [[String:AnyObject]]{
            
            for var record in records {
                
                if let userId = userId, let usersName = usersName {
                    
                    var user = [String : AnyObject]()
                    user["name"] = usersName
                    user["_id"] = userId
                    record["user"] = user

                }
                
                
                if let image = Image(record){
                    images.append(image)
                }
            }
  
        }
        
        return images
    }
    
    
    func getUsers(){
        
        let requestURL = getBluemixBaseRequestURL() + "/" + kUsersEndPoint
        
        let request = Request(url: requestURL, method: HttpMethod.GET)
        
        request.sendWithCompletionHandler { (response, error) -> Void in
            if let error = error {
                print ("Error :: \(error)")
            } else {
                print ("Success :: \(response?.responseText)")
            }
        }
        
    }
    
    func getUserById(userId : String, result: (user : User?) -> ()){
        
        let requestURL = getBluemixBaseRequestURL() + "/" + kUsersEndPoint + "/" + userId
        
        let request = Request(url: requestURL, method: HttpMethod.GET)
        
        request.sendWithCompletionHandler { (response, error) -> Void in
            if let error = error {
                print ("Error Getting User By Id :: \(error)")
               result(user: nil)
            } else {
                let user = User(response)
                result(user: user)
                print ("Success :: \(response?.responseText)")
            }
        }
    }
    
    func doesUserAlreadyExist(userId : String, result : (doesUserAlreadyExist : Bool) -> ()){
    
        getUserById(userId, result: { user in
            
            if user != nil {
                result(doesUserAlreadyExist: true)
            }
            else{
                result(doesUserAlreadyExist: false)
            }
            
        })
    }
    
    
    private func createNewUser(userId : String, name : String, result : ((user : User?) -> ())){
        
        let requestURL = getBluemixBaseRequestURL() + "/" + kUsersEndPoint
        
        let request = Request(url: requestURL, method: HttpMethod.POST)
        
        //request.headers = ["Content-Type" : "application/json"]
        
        let json = ["_id": userId, "name": name]

        
        do{
            let jsonData = try NSJSONSerialization.dataWithJSONObject(json, options: .PrettyPrinted)
            
            request.sendData(jsonData, completionHandler: { (response, error) -> Void in
                if let error = error {
                    result(user: nil)
                    print ("Error  Creating New User :: \(error)")
                } else {
                    let user = User(response)
                    result(user: user)
                    print ("Success :: \(response?.responseText)")
                }
            })
            
        } catch {
            result(user: nil)
            
        }
        
    }
    
    
    func checkIfUserAlreadyExistsIfNotCreateNewUser(userId : String, name : String, callback : ((success : Bool) -> ())){

        getUserById(userId, result: { user in
            
            if(user != nil){
               callback(success: true)
            }
            else{
                self.createNewUser(userId, name: name, result: { user in
                    
                    if(user != nil){
                        callback(success: true)
                    }
                    else{
                        callback(success: false)
                    }

                })
            }
            
        })

    }
    
    

    func createNewUserIfUserDoesntAlreadyExistElseReturnExistingUser(userId : String, name : String, result : ((user : User?) -> ())){
        
        getUserById(userId, result: { user in
            
            if let user = user {
                result(user: user)
            }
            else{
                self.createNewUser(userId, name: name, result: { user in
                    result(user: user)
                })
            }
   
        })
    }
    
    
    
    func postNewImage(image : Image){
        
        NSNotificationCenter.defaultCenter().postNotificationName(BluemixDataManagerNotification.ImageUploadBegan.rawValue, object: nil)
    
        //TEMP HARDCODED
        let latitude = "37.864851"
        let longitude = "119.538523"
        let city = "Austin"
        
        let tempURL = getBluemixBaseRequestURL() + "/" + kUsersEndPoint + "/" + CurrentUser.facebookUserId! + "/" + kImagesEndPoint + "/" + image.fileName! + "/" + image.caption! + "/" + "\(image.width!)" + "/" + "\(image.height!)" + "/" + latitude + "/" + longitude + "/" + city
        
        let requestURL = tempURL.stringByAddingPercentEncodingWithAllowedCharacters( NSCharacterSet.URLQueryAllowedCharacterSet())!

        let request = Request(url: requestURL, method: HttpMethod.POST)
  
        request.headers = ["Content-Type" : "image/png"]
        
        request.sendData(UIImagePNGRepresentation(image.image!)!, completionHandler: { (response, error) -> Void in
            
            if(error != nil){
                NSNotificationCenter.defaultCenter().postNotificationName(BluemixDataManagerNotification.ImageUploadFailure.rawValue, object: nil)
            } else {
  
                self.removeImageFromImageUploadQueue(image)
                
                self.uploadImagesIfThereAreAnyLeftInTheQueue()
                
                NSNotificationCenter.defaultCenter().postNotificationName(BluemixDataManagerNotification.ImageUploadSuccess.rawValue, object: nil)
 
            }
        })
    
    }
    
    
 
    
}


//UPLOADING IMAGES
extension BluemixDataManager {
    
    
    func uploadImage(image : Image){
        
        self.addImageToImageTakenDuringAppSessionByIdDictionary(image)
        self.addImageToImageUploadQueue(image)

        tryToPostNewImage(image)
 
    }
    
    private func tryToPostNewImage(image : Image){
        
        if(imageUploadQueue.count == 1){
            postNewImage(image)
        }
    }

    
    private func removeImageFromImageUploadQueue(image: Image){
        
        imageUploadQueue = imageUploadQueue.filter({ $0 !== image})
        
    }
    
    
    private func uploadImagesIfThereAreAnyLeftInTheQueue(){
        
        if(imageUploadQueue.count > 0){
            postNewImage(imageUploadQueue[0])
        }
    }
    
    /**
     Method adds the photo to the picturesTakenDuringAppSessionById cache to display the photo in the image feed while we wait for the photo to upload to.
     */
    private func addImageToImageTakenDuringAppSessionByIdDictionary(image : Image){
        
        if let fileName = image.fileName, let userID = image.usersId {
            
            let id = fileName + userID
            imagesTakenDuringAppSessionById[id] = image.image
            
        }
    }
    
    /**
     Method creates a new picture object and adds it to the picture upload queue
     
     - returns: Picture
     */
    private func addImageToImageUploadQueue(image : Image) {
        imageUploadQueue.append(image)
    }


    
}
