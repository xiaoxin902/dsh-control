// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OwnGoal Studio
#import "SceneDelegate.h"
#import "RootViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[RootViewController new]];
    navigation.navigationBar.prefersLargeTitles = YES;
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
}

@end
