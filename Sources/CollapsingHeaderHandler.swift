//
//  CollapsingCollectionViewLayout.swift
//  Sundial
//
//  Created by Sergei Mikhan on 11/21/17.
//

import UIKit
import RxSwift
import RxCocoa

class CollapsingHeaderHandler {

  let headerHeight: BehaviorRelay<CGFloat>
  let minHeaderHeight: BehaviorRelay<CGFloat>
  let maxHeaderHeight: BehaviorRelay<CGFloat>
  let headerInset: BehaviorRelay<CGFloat>
  let followOffsetChanges: BehaviorRelay<Bool>

  weak var collapsingItem: CollapsingItem?

  enum ConnectionStatus: Int {
    case none
    case connected
    case disconnected
  }

  private var connection: ConnectionStatus = .none
  private var activeDispose: Disposable?
  private var nonActiveDispose: Disposable?
  private let disposeBag = DisposeBag()
  private var collapsingBorder: CGFloat = 0.0

  init(with collapsingItem: CollapsingItem,
       min: BehaviorRelay<CGFloat>,
       max: BehaviorRelay<CGFloat>,
       headerInset: BehaviorRelay<CGFloat>,
       headerHeight: BehaviorRelay<CGFloat>,
       followOffsetChanges: BehaviorRelay<Bool>) {

    self.collapsingItem = collapsingItem
    self.minHeaderHeight = min
    self.maxHeaderHeight = max
    self.headerHeight = headerHeight
    self.headerInset = headerInset
    self.followOffsetChanges = followOffsetChanges

    headerHeight.asDriver().drive(onNext: { [weak collapsingItem] height in
      collapsingItem?.headerHeightDidChange(height)
    }).disposed(by: disposeBag)

    let contentSizeDriver = collapsingItem.scrollView.rx
      .observe(CGSize.self, #keyPath(UICollectionView.contentSize))
      .flatMap { size -> Observable<CGSize> in
        guard let size = size else { return .empty() }
        return .just(size)
      }
      .asDriver(onErrorJustReturn: .zero)
      .filter { $0.width != 0.0 && $0.height != 0.0 }
      .distinctUntilChanged { $0.height == $1.height }

    let scrollViewHeightDriver = collapsingItem.scrollView.rx
      .observe(CGRect.self, #keyPath(UICollectionView.bounds))
      .flatMap { rect -> Observable<CGFloat> in
        guard let rect = rect else { return .empty() }
        return .just(rect.height)
      }
      .asDriver(onErrorJustReturn: 0)
      .filter { $0 != 0 }
      .distinctUntilChanged()

    Driver.combineLatest(contentSizeDriver, scrollViewHeightDriver, maxHeaderHeight.asDriver())
      .drive(onNext: { [weak collapsingItem = self.collapsingItem, weak self] contentSize, height, maxHeight in
        guard let sself = self else { return }
        guard let collapsingItem = collapsingItem else { return }

        let extraInset = collapsingItem.extraInset
        let topInset = maxHeight + sself.headerInset.value + extraInset.top
        var bottomInset: CGFloat = height - (contentSize.height + sself.minHeaderHeight.value + sself.headerInset.value + extraInset.bottom)
        if bottomInset < 0.0  {
          bottomInset = extraInset.bottom
        }

        let contentOffsetOriginal = collapsingItem.scrollView.contentOffset
        let adjustedY = -(sself.headerHeight.value + sself.headerInset.value)
        let contentOffset = CGPoint(x: contentOffsetOriginal.x, y: adjustedY)

        collapsingItem.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        collapsingItem.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        // FIXME: we need to avoid unnecessary content offset change when content size changed
        if collapsingItem.scrollView.contentOffset.y <= 0.0 {
          collapsingItem.scrollView.contentOffset = contentOffset
        }
      }).disposed(by: disposeBag)
  }

  func connect() {
    guard connection != .connected else { return }
    connection = .connected

    guard let collapsingItem = collapsingItem else { return }
    let targetContentOffset = -headerHeight.value - headerInset.value
    if collapsingItem.scrollView.contentOffset.y <= 0.0 {
      collapsingItem.scrollView.contentOffset = CGPoint(x: 0, y: targetContentOffset)
    }
    activeDispose?.dispose()
    nonActiveDispose?.dispose()

    let headerHeightDispose = collapsingItem.scrollView.rx.contentOffset
      .asObservable()
      .skip(1)
      .distinctUntilChanged()
      .filter { [weak self] _ in
        guard let `self` = self else { return false }
        let scrollView = collapsingItem.scrollView

        let isScrollingToTop = scrollView.isScrollingToTop

        return scrollView.panGestureRecognizer.state != .possible
          || scrollView.isDecelerating
          || scrollView.isDragging
          || scrollView.isTracking
          || isScrollingToTop
          || self.followOffsetChanges.value != false
      }
      .map { [unowned self] input in
        let offset = self.collapsingBorder - input.y - self.headerInset.value
        return min(max(self.minHeaderHeight.value, offset), self.maxHeaderHeight.value)
      }.asDriver(onErrorJustReturn: maxHeaderHeight.value)
      .distinctUntilChanged()
      .drive(headerHeight)

    let maxHeaderHeightDispose = maxHeaderHeight
      .asDriver()
      .skip(1)
      .withLatestFrom(headerHeight.asDriver()) { ($0, $1) }
      .drive(onNext: { [weak collapsingItem = self.collapsingItem] maxHeight, height in
        if maxHeight == height {
          collapsingItem?.scrollView.contentOffset = CGPoint(x: 0, y: -maxHeight - self.headerInset.value)
        }
      })

    if collapsingItem.followDirection {
      self.collapsingBorder = collapsingItem.scrollView.contentOffset.y + headerHeight.value + self.headerInset.value
      if self.collapsingBorder < 0.0 {
        self.collapsingBorder = 0.0
      }
      let directionChangeDispose = directionChange().subscribe(onNext: { [weak self] value in
        guard let `self` = self else { return }
        guard let scrollView = self.collapsingItem?.scrollView else { return }
        self.collapsingBorder = scrollView.contentOffset.y + self.headerHeight.value + self.headerInset.value
        if self.collapsingBorder < 0.0 {
          self.collapsingBorder = 0.0
        }
      })
      activeDispose = Disposables.create(headerHeightDispose, maxHeaderHeightDispose, directionChangeDispose)
    } else {
      activeDispose = Disposables.create(headerHeightDispose, maxHeaderHeightDispose)
    }
  }

  func disconnect() {
    guard connection != .disconnected else { return }
    connection = .disconnected

    activeDispose?.dispose()
    nonActiveDispose?.dispose()
    if let collapsingItem = collapsingItem {
      nonActiveDispose = headerHeight
        .asDriver()
        .distinctUntilChanged()
        .skip(1)
        .map {
          return CGPoint(x: 0, y: -$0 - self.headerInset.value)
        }.drive(collapsingItem.scrollView.rx.contentOffset)
    }
  }

  enum Direction {
    case topToBottom
    case bottomToTop
  }

  fileprivate func directionChange() -> Observable<Direction> {
    guard let collapsingItem = collapsingItem else { return .empty() }
    let current = collapsingItem.scrollView.rx.contentOffset
      .map { $0.y }
      .filter { [weak self] _ in
        guard let scrollView = self?.collapsingItem?.scrollView else { return false }
        return !scrollView.isBouncing
      }.distinctUntilChanged()
    let previous = current.skip(1)
    return Observable.zip(current, previous).map { offsets -> Direction in
      return offsets.0 > offsets.1 ? .topToBottom : .bottomToTop
    }.buffer(timeSpan: .seconds(1), count: 5, scheduler: MainScheduler.instance)
    .flatMap { directions -> Observable<Direction> in
      guard !directions.isEmpty else { return .empty() }
      if directions.filter({ $0 == .topToBottom }).isEmpty {
        return .just(.topToBottom)
      } else if directions.filter({ $0 == .bottomToTop }).isEmpty {
        return .just(.bottomToTop)
      } else {
        return .empty()
      }
    }.distinctUntilChanged()
  }

  deinit {
    activeDispose?.dispose()
    nonActiveDispose?.dispose()
  }
}

extension UIScrollView {

  var isBouncing: Bool {
    return isBouncingTop || isBouncingBottom
  }

  var isBouncingTop: Bool {
    return contentOffset.y < -contentInset.top
  }

  var isBouncingBottom: Bool {
    let contentFillsScrollEdges = contentSize.height + contentInset.top + contentInset.bottom >= bounds.height
    return contentFillsScrollEdges && contentOffset.y > contentSize.height - bounds.height + contentInset.bottom
  }
}
