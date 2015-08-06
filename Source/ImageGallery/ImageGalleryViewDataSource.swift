import UIKit

extension ImageGalleryView: UICollectionViewDataSource {

  struct CollectionView {
    static let reusableIdentifier = "imagesReusableIdentifier"
  }

  func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    displayNoImagesMessage(images.count == 0)
    return images.count
  }

  func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCellWithReuseIdentifier(CollectionView.reusableIdentifier,
      forIndexPath: indexPath) as! ImageGalleryViewCell

    let image = images[indexPath.row] as! UIImage
    
    cell.configureCell(image)

    if indexPath.row == 0 && shouldTransform {
      cell.transform = CGAffineTransformMakeScale(0, 0)

      UIView.animateWithDuration(0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .CurveEaseInOut, animations: { [unowned self] in
        cell.transform = CGAffineTransformIdentity
        }, completion: nil)

      shouldTransform = false
    }

    if selectedImages.containsObject(image) {
      cell.selectedImageView.image = getImage("selectedImageGallery")
    } else {
      cell.selectedImageView.image = nil
    }

    return cell
  }
}
