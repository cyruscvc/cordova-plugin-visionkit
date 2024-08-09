#import <Foundation/Foundation.h>
#import "VisionKit.h"

#define RL_SCAN_PREFIX @"rl_scan_"

@implementation VisionKit

@synthesize documentCameraViewController;

- (void)scan:(CDVInvokedUrlCommand*)command {
    // Retrieve the endpoint and apiKey from the command arguments
    NSString *endpoint = [[command arguments] objectAtIndex:0];
    NSString *apiKey = [[command arguments] objectAtIndex:1];
    
    // Save them to instance variables for later use
    self.azureEndpoint = endpoint;
    self.azureApiKey = apiKey;
    
    callbackId = command.callbackId;
    
    [self showScanOrGalleryOptions];
}

- (void)documentCameraViewController:(VNDocumentCameraViewController *)controller didFinishWithScan:(VNDocumentCameraScan *)scan {
    [self showLoadingSpinnerInView:self.documentCameraViewController.view];
    
    __weak VisionKit* weakSelf = self;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        UIImage *image = [scan imageOfPageAtIndex:0];
        [weakSelf processImage:image];

        // Proceed with OCR after image processing
        [weakSelf performOCRWithImage:image];
        
        [controller dismissViewControllerAnimated:YES completion:nil];
    });
}

#pragma mark - Azure OCR Integration

- (void)performOCRWithImage:(UIImage *)image {
    NSData *imageData = UIImageJPEGRepresentation(image, 0.5);  // Adjust compression as needed
    NSString *base64Image = [imageData base64EncodedStringWithOptions:0]; // Convert to Base64 string

    // Use the stored endpoint and apiKey
    NSString *endpoint = [NSString stringWithFormat:@"%@/formrecognizer/documentModels/prebuilt-receipt:analyze?api-version=2023-07-31", self.azureEndpoint];
    NSString *apiKey = self.azureApiKey;
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [request setValue:apiKey forHTTPHeaderField:@"Ocp-Apim-Subscription-Key"];
    [request setHTTPBody:imageData];
    
    // Perform the request (asynchronous)
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Error: %@", error.localizedDescription);
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
        
        if (jsonError) {
            NSLog(@"JSON Parsing Error: %@", jsonError.localizedDescription);
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:jsonError.localizedDescription];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];
            return;
        }
        
        NSLog(@"OCR Response: %@", responseDict);
        
        // Extract relevant information from OCR response
        NSDictionary *analyzeResult = responseDict[@"analyzeResult"];
        NSArray *documents = analyzeResult[@"documents"];
        
        NSMutableDictionary *receiptInfo = [NSMutableDictionary dictionary];
        
        if (documents.count > 0) {
            NSDictionary *fields = documents[0][@"fields"];
            
            // Extract Date
            NSDictionary *dateField = fields[@"TransactionDate"];
            if (dateField) {
                receiptInfo[@"date"] = dateField[@"content"];
            }
            
            // Extract Total Amount
            NSDictionary *totalField = fields[@"Total"];
            if (totalField) {
                receiptInfo[@"totalAmount"] = totalField[@"content"];
            }
            
            // Extract Merchant Name
            NSDictionary *merchantNameField = fields[@"MerchantName"];
            if (merchantNameField) {
                receiptInfo[@"merchantName"] = merchantNameField[@"content"];
            }
            
            // Extract Currency Code (if available)
            NSDictionary *currencyField = fields[@"Currency"];
            if (currencyField) {
                receiptInfo[@"currencyCode"] = currencyField[@"content"];
            }
        }
        
        // Add the Base64 image string to the response
        receiptInfo[@"base64Image"] = base64Image;
        
        // Return the extracted receipt information along with the Base64 image
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:receiptInfo];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];
    }];
    
    [dataTask resume];
}

#pragma mark - UI Methods

- (void)showScanOrGalleryOptions {
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
    dispatch_async(dispatch_get_main_queue(), ^{
        self.documentCameraViewController = [VNDocumentCameraViewController new];
        self.documentCameraViewController.delegate = self;
        [self.viewController presentViewController:self.documentCameraViewController animated:YES completion:nil];
    });
}

- (void)showGallery {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
        imagePicker.delegate = self;
        imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        
        [self.viewController presentViewController:imagePicker animated:YES completion:nil];
    });
}

- (void)showLoadingSpinnerInView:(UIView *)view {
    UIView* loadingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    loadingView.center = view.center;
    loadingView.backgroundColor = [UIColor whiteColor];
    loadingView.clipsToBounds = YES;
    loadingView.layer.cornerRadius = 10;

    UIActivityIndicatorView* spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = CGPointMake(loadingView.frame.size.width / 2, loadingView.frame.size.height / 2);
    [spinner startAnimating];
    
    [loadingView addSubview:spinner];
    [view addSubview:loadingView];
}

- (void)hideLoadingSpinnerInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIActivityIndicatorView class]]) {
            [subview removeFromSuperview];
        }
    }
}

#pragma mark - Image Processing

- (void)processImage:(UIImage *)image {
    __weak VisionKit* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showLoadingSpinnerInView:self.viewController.view];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSMutableArray* images = [@[] mutableCopy];
            CDVPluginResult* pluginResult = nil;
            
            @try {
                // Resize and compress the image
                UIImage *resizedImage = [self resizeImage:image toPercentage:0.5];
                NSData* imageData = UIImageJPEGRepresentation(resizedImage, 0.5);
                
                NSString* filePath = [self tempFilePath:@"jpg"];
                NSError* err = nil;

                if (![imageData writeToFile:filePath options:NSAtomicWrite error:&err]) {
                    @throw [NSException exceptionWithName:@"FileWriteException" reason:[err localizedDescription] userInfo:nil];
                }

                NSString* strBase64 = [self encodeToBase64String:resizedImage];
                [images addObject:strBase64];
                
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:images];
            }
            @catch (NSException *exception) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:exception.reason];
            }
            @finally {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:self->callbackId];
                    [weakSelf hideLoadingSpinnerInView:weakSelf.viewController.view];
                });
            }
        });
    });
}

- (UIImage *)resizeImage:(UIImage *)image toPercentage:(CGFloat)percentage {
    CGSize newSize = CGSizeMake(image.size.width * percentage, image.size.height * percentage);
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resizedImage;
}

- (NSString *)encodeToBase64String:(UIImage *)image {
    return [UIImagePNGRepresentation(image) base64EncodedStringWithOptions:kNilOptions];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
    [self processImage:selectedImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: @[]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

#pragma mark - VNDocumentCameraViewControllerDelegate

- (void)documentCameraViewController:(VNDocumentCameraViewController *)controller didFinishWithScan:(VNDocumentCameraScan *)scan {
    [self showLoadingSpinnerInView:self.documentCameraViewController.view];
    
    __weak VisionKit* weakSelf = self;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 0.5);
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        UIImage *image = [scan imageOfPageAtIndex:0];
        [weakSelf processImage:image];
        [controller dismissViewControllerAnimated:YES completion:nil];
    });
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

#pragma mark - Utility

- (NSString*)tempFilePath:(NSString*)extension {
    NSString* docsPath = [NSTemporaryDirectory() stringByStandardizingPath];
    NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe
    NSString* filePath;

    do {
        filePath = [NSString stringWithFormat:@"%@/%@%ld.%@", docsPath, RL_SCAN_PREFIX, (long)[NSDate timeIntervalSinceReferenceDate], extension];
    } while ([fileMgr fileExistsAtPath:filePath]);

    return filePath;
}

@end
