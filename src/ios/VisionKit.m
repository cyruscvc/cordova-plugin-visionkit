#import "VisionKit.h"

#define RL_SCAN_PREFIX @"rl_scan_"

@implementation VisionKit

@synthesize documentCameraViewController;

- (void)scan:(CDVInvokedUrlCommand*)command {
    callbackId = command.callbackId;
    
    // Adding option to choose between scanning and selecting from gallery
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select Option"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *scanAction = [UIAlertAction actionWithTitle:@"Scan Document" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showScanUI];
    }];
    
    UIAlertAction *galleryAction = [UIAlertAction actionWithTitle:@"Select from Gallery" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showGallery];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:scanAction];
    [alert addAction:galleryAction];
    [alert addAction:cancelAction];
    
    [self.viewController presentViewController:alert animated:YES completion:nil];
}

- (void)showScanUI {
    // Perform UI operations on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        self.documentCameraViewController = [VNDocumentCameraViewController new];
        self.documentCameraViewController.delegate = self;
        
        [self.viewController presentViewController:self.documentCameraViewController animated:YES completion:nil];
    });
}

- (void)showGallery {
    // Perform UI operations on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
        imagePicker.delegate = self;
        imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        
        [self.viewController presentViewController:imagePicker animated:YES completion:nil];
    });
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
    [self processImage:selectedImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)processImage:(UIImage *)image {
    __weak VisionKit* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Present a loading spinner
        UIView* loadingView = [[UIView alloc] init];
        loadingView.frame = CGRectMake(0, 0, 80, 80);
        loadingView.center = self.viewController.view.center;
        loadingView.backgroundColor = [UIColor whiteColor];
        loadingView.clipsToBounds = true;
        loadingView.layer.cornerRadius = 10;

        UIActivityIndicatorView* spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        spinner.center = CGPointMake(loadingView.frame.size.width / 2, loadingView.frame.size.height / 2);
        [spinner startAnimating];

        // Add the views to the UI
        [loadingView addSubview:spinner];
        [self.viewController.view addSubview:loadingView];

        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
        dispatch_after(delay, dispatch_get_main_queue(), ^{
            NSMutableArray* images = [@[] mutableCopy];
            CDVPluginResult* pluginResult = nil;

            NSLog(@"Processing selected image");

            // Resize the image to a smaller size (e.g., 50% of the original size)
            CGSize newSize = CGSizeMake(image.size.width * 0.5, image.size.height * 0.5);
            UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
            [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
            UIImage* resizedImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            // Compress the resized image with a lower quality
            NSData* imageData = UIImageJPEGRepresentation(resizedImage, 0.5);

            NSString* filePath = [self tempFilePath:@"jpg"];
            NSError* err = nil;

            if (![imageData writeToFile:filePath options:NSAtomicWrite error:&err]) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];
                return;
            }

            NSString* strBase64 = [self encodeToBase64String:resizedImage];
            [images addObject:strBase64];

            NSLog(@"%@", images);

            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: images];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];

            [loadingView removeFromSuperview];
        });
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: @[]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)documentCameraViewController:(VNDocumentCameraViewController *)controller didFinishWithScan:(VNDocumentCameraScan *)scan {
    // Present a loading spinner
    UIView* loadingView = [[UIView alloc] init];
    loadingView.frame = CGRectMake(0, 0, 80, 80);
    loadingView.center = self.documentCameraViewController.view.center;
    loadingView.backgroundColor = [UIColor whiteColor];
    loadingView.clipsToBounds = true;
    loadingView.layer.cornerRadius = 10;
    
    UIActivityIndicatorView* spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    
    spinner.center = CGPointMake(loadingView.frame.size.width / 2, loadingView.frame.size.height / 2);
    [spinner startAnimating];
    
    // Add the views to the UI
    [loadingView addSubview:spinner];
    [[self.documentCameraViewController view] addSubview:loadingView];
    
    [[self.documentCameraViewController view] setNeedsDisplay];
    
    __weak VisionKit* weakSelf = self;
    
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^(void){
        NSMutableArray* images = [@[] mutableCopy];
        CDVPluginResult* pluginResult = nil;

        // Process only the first scanned page
        NSLog(@"Processing scanned image 0");
        
        NSString* filePath = [self tempFilePath:@"jpg"];
        NSLog(@"Got image file path image 0, %@", filePath);
        
        UIImage* image = [scan imageOfPageAtIndex: 0];
        NSData* imageData = UIImageJPEGRepresentation(image, 0.7);
        
        NSLog(@"Got image data image 0");

        NSError* err = nil;

        if (![imageData writeToFile:filePath options:NSAtomicWrite error:&err]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId: self->callbackId];
            return;
        }
        
        NSLog(@"Adding file to `images` array: %@", filePath);
        
        NSString* strBase64 = [self encodeToBase64String:image];

        NSLog(@"Base64 string: %@", strBase64);
        
        [images addObject:strBase64];
        
        NSLog(@"%@", images);
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: images];
        [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];
        
        [controller dismissViewControllerAnimated:YES completion:nil];
        NSLog(@"Dismiss scanner");
    });
}

- (NSString *)encodeToBase64String:(UIImage *)image {
 return [UIImagePNGRepresentation(image) base64EncodedStringWithOptions:kNilOptions];
}

- (void)documentCameraViewControllerDidCancel:(VNDocumentCameraViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: @[]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)documentCameraViewController:(VNDocumentCameraViewController *)controller didFailWithError:(NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

// Borrowed from https://github.com/apache/cordova-plugin-camera/blob/master/src/ios/CDVCamera.m#L396
- (NSString*)tempFilePath:(NSString*)extension {
    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
    NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe
    NSString* filePath;

    // unique file name
    NSTimeInterval timeStamp;
    NSNumber *timeStampObj;
    
    do {
        timeStamp = [[NSDate date] timeIntervalSince1970];
        timeStampObj = [NSNumber numberWithDouble: timeStamp];
        filePath = [NSString stringWithFormat:@"%@/%@%ld.%@", docsPath, RL_SCAN_PREFIX, [timeStampObj longValue], extension];
    } while ([fileMgr fileExistsAtPath:filePath]);

    return filePath;
}

@end
