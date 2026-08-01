import { apiInitializer } from "discourse/lib/api";
import ArcadeRecordFlair from "../components/arcade-record-flair";

export default apiInitializer((api) => {
  // After the wrapper, not in it. post-meta-data-poster-name wraps the username
  // link, and renderInOutlet replaces a wrapper outlet's content rather than
  // adding to it, which silently removes the username from every post.
  //
  // The server leaves arcade_records off the post entirely unless the setting is
  // on and the poster actually holds something, so there is nothing to check
  // here: the component renders nothing when the field is absent.
  api.renderAfterWrapperOutlet("post-meta-data-poster-name", ArcadeRecordFlair);
});
