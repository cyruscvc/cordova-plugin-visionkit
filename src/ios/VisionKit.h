#import <Cordova/CDV.h>
#import <VisionKit/VisionKit.h>

@interface VisionKit : CDVPlugin<VNDocumentCameraViewControllerDelegate> {
    NSString* callbackId;
}

@property (nonatomic, strong) NSString *azureEndpoint;
@property (nonatomic, strong) NSString *azureApiKey;
@property (strong) VNDocumentCameraViewController* documentCameraViewController;

- (void) scan:(CDVInvokedUrlCommand*)command;

@end
